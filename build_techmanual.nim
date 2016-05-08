import options
import nre
import os
import osproc
import strutils

var beg_e=re"(?m)^#\+BEGIN_EXAMPLE$"
var end_e=re"(?m)^#\+END_EXAMPLE$"

var strip_html=re"(?s)#\+BEGIN_HTML.*?#\+END_HTML"


let arguments = commandLineParams()

for file in arguments:
  let (path, filen, ext) = os.splitFile(file)
  var test =""
  if ext == ".txt":
    test=execProcess( @["/usr/bin/pandoc","-f","rst","-t","org", file].join(" "),@[] )
  elif ext == ".md":
    test=execProcess( @["/usr/bin/pandoc","-f","markdown","-t","org", file].join(" "),@[] )
  else:
    try:
      test = readFile(file)
    except:
        echo "Cannot Parse: " & file
        break
  test = test.replace(beg_e,"#+BEGIN_SRC nim")
  test = test.replace(end_e,"#+END_SRC")
  test = test.replace(strip_html,"")
  echo test



# Local Variables:
# firestarter: "nim c -d:release post_pandoc.nim || notify-send -u low 'nim' 'compile error on post_pandoc.nim'"
# End:
