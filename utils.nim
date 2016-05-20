import strutils

proc strip_string*(s:string):string{.procvar.}=
  strip(s)

proc isSomeString*(s:string):bool{.procvar.}=
  s!=""
