import std/[hashes, os, osproc, strutils]

const
  nimArgsPrefix = "#nimbang-args "
  nimbangSettingsPrefix = "#nimbang-settings "

# Inspect command line parameters
let args =  commandLineParams()

if args.len == 0:
  stderr.write "Usage on the command line: nimbang filename [arguments to program]\n"
  stderr.write "Usage in a script:\n"
  stderr.write "    [1] add `#!/usr/bin/env nimbang` to your script as first line\n"
  stderr.write "    [2] (optional) add `#nimbang-args [arguments for nim compiler]` to your script as second line\n"
  stderr.write "    [3] (optional) add `#nimbang-settings [settings for nimbang]` to your script as third line\n"
  quit(-1)

let
  filename = args[0].expandFilename
  baseCacheDir =
    when defined(windows):
      getTempDir() / "nimbang"
    else:
      let home = getHomeDir()
      if dirExists(home): 
        home / ".cache" / "nimbang"
      else:
        getTempDir() / "nimbang"
  nimCacheDir = baseCacheDir / ("nimcache-" & filename.hash.toHex)

try:
  createDir(baseCacheDir)
except OSError:
  echo "Failed to create directory: ", getCurrentExceptionMsg()
  quit(1)

let
  splitName = filename.splitfile
  exeName = nimCacheDir / (splitName.name) / (when defined(windows): ".exe" else: "")

# Compilation of script if target doesn't exist
var
  buildStatus = 0
  output = ""
  command = ""

if not exeName.fileExists or filename.fileNewer(exeName):
  var
    nimArgs = ""
    nimbangSettings: seq[string] = @[]  # supported settings: hidedebuginfo
    showDebugInfo = false
  # Get extra arguments for nim compiler from the second line (it must start with #nimbang-args [args] )
  block:
    for line in filename.lines:
      if line.len == 0 or line[0] != '#':
        break
      if line.startsWith(nimArgsPrefix):
        nimArgs &= line[nimArgsPrefix.len .. ^1]
        if not nimArgs.contains("-d:debug"):
            nimArgs &= " -d:release"
        echo nimArgs
      if line.startsWith(nimbangSettingsPrefix):
        nimbangSettings = line[nimbangSettingsPrefix.len .. ^1].strip.toLower.split
        showDebugInfo = nimbangSettings.contains("showdebuginfo")
        break

  exeName.removeFile
  command = "nim c " & nimArgs & " --colors:on --nimcache:\"" &
    nimCacheDir & "\"" &
    " --out:\"" & exeName & "\" \"" & filename & "\""  # dxbb's patch
  if showDebugInfo:
    stderr.write "# Running command: " & command & "\n"
    stderr.write "# ----------------\n"

  (output, buildStatus) = execCmdEx(command)

# Run the target, or show an error
if buildStatus == 0:
  let p = startProcess(exeName,  args=args[args.low+1 .. ^1],
                       options={poStdErrToStdOut, poParentStreams, poUsePath})
  let res = p.waitForExit()
  p.close()
  quit(res)
else:
  stderr.write "(nimbang) Error on build running command: " & command & "\n"
  stderr.write output
  quit(buildStatus)
