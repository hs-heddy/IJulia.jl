#######################################################################
import JSON, Conda
using Compat

jupyter=""

# remove deps.jl at exit if it exists, in case build.jl fails
try
#######################################################################

# Make sure Python uses UTF-8 output for Unicode paths
ENV["PYTHONIOENCODING"] = "UTF-8"

function prog_version(prog)
    try
       return convert(VersionNumber, chomp(readstring(`$prog --version`)))
    catch
       return v"0.0"
    end
end

global jupyter = get(ENV, "JUPYTER", isfile("JUPYTER") ? readchomp("JUPYTER") : Compat.Sys.islinux() ? "jupyter" : "")
jupyter_vers = isempty(jupyter) ? v"0.0" : prog_version(jupyter)
if (jupyter_vers == v"0.0")                                                     # some Linux distributions (Debian) use jupyter-notebook to launch Jupyter
    jupyter_vers = prog_version(jupyter * "-notebook")
end
isconda = dirname(jupyter) == abspath(Conda.SCRIPTDIR)
if Sys.ARCH in (:i686, :x86_64) && (jupyter_vers < v"3.0" || isconda)
    isempty(jupyter) || isconda || info("$jupyter was too old: got $jupyter_vers, required ≥ 3.0")
    info("Installing Jupyter via the Conda package.")
    Conda.add("jupyter")
    jupyter = abspath(Conda.SCRIPTDIR, "jupyter")
    jupyter_vers = prog_version(jupyter)
end
if jupyter_vers < v"3.0"
    error("Failed to find or install Jupyter 3.0 or later. Please install Jupyter manually, set `ENV[\"JUPYTER\"]=\"/path/to/jupyter\", and rerun `Pkg.build(\"IJulia\")`.")
end
info("Found Jupyter version $jupyter_vers: $jupyter")

#######################################################################
# Get the latest syntax highlighter file.
if isconda
    highlighter = joinpath(Conda.LIBDIR, "python2.7", "site-packages", "notebook", "static",
                           "components", "codemirror", "mode", "julia", "julia.js")
    # CodeMirror commit from which we get the syntax highlighter
    cm_commit = "d444cd1007bd32e418ace8ffed1cb0e692ee147d"
    highlighter_url = "https://raw.githubusercontent.com/codemirror/CodeMirror/" *
                      cm_commit * "/mode/julia/julia.js"
    if isfile(highlighter)
        try
            download(highlighter_url, highlighter)
        catch e
            warn("The following error occurred while attempting to download latest ",
                 "syntax highlighting definitions:\n\n", e, "\n\nSyntax highlighting may ",
                 "not work as expected.")
        end
    end
end

#######################################################################
# Warn people upgrading from older IJulia versions:
try
    juliaprof = chomp(readstring(pipeline(`$ipython locate profile julia`,
                                          stderr=DevNull)))
    warn("""You should now run IJulia just via `$jupyter notebook`, without
            the `--profile julia` flag.  IJulia no longer maintains the profile.
            Consider deleting $juliaprof""")
end

#######################################################################
# Install Jupyter kernel-spec file.

include("kspec.jl")
kspec_cmd, = installkernel("Julia")

# figure out the notebook command by replacing (only!) the last occurrence of
# "kernelspec" with "notebook":
notebook = kspec_cmd.exec
n = notebook[end]
ki = rsearch(n, "kernelspec")
notebook[end] = n[1:prevind(n,first(ki))] * "notebook" * n[nextind(n,last(ki)):end]

#######################################################################
# Install the deps.jl file:

if v"4.2" ≤ jupyter_vers < v"5.1"
    # disable broken data-rate limit (issue #528)
    push!(notebook, "--NotebookApp.iopub_data_rate_limit=2147483647")
end
deps = """
    const jupyter = "$(escape_string(jupyter))"
    const notebook_cmd = ["$(join(map(escape_string, notebook), "\", \""))"]
    const jupyter_vers = $(repr(jupyter_vers))
    """
if !isfile("deps.jl") || readstring("deps.jl") != deps
    write("deps.jl", deps)
end
write("JUPYTER", jupyter)

#######################################################################
catch
isfile("deps.jl") && rm("deps.jl") # remove deps.jl file on build error
rethrow()
end
