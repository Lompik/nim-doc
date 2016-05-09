import json
import strutils
import os
import osproc
import nre
import tables

type symbol_type = enum
  skConst=0, skIterator, skLet, skProc, skTemplate, skType, skVar, skMacro, skConverter
var symbols, symbols_empty = {
  "skConst": (skConst,"@vindex","","Constant variables"),
  "skIterator": (skIterator,"@findex","","Iterators"),
  "skLet": (skLet,"@vindex","","Let variable"),
  "skProc": (skProc,"@findex","","Procedures"),
  "skTemplate": (skTemplate,"@findex","","Templates"),
  "skType": (skType,"@vindex","","Types"),
  "skMacro": (skMacro,"@findex","","Macros"),
  "skConverter": (skConverter,"@findex","","Converter"),
  "skMethod": (skConverter,"@findex","","Methods"),
  "skVar": (skVar,"@vindex","","Variables")}.totable

proc texize(txt:string):string=
  txt.replace("@", "@@").replace("}","@}").replace("{","@{")


var  tmpname = getTempDir().joinPath("jjjjjiiii516516156161")
proc parse_symb_json(n_json:JsonNode, module:string)=
  symbols=symbols_empty
  for i in countUp(0,n_json.len- 1):
    var output="\n\n"
    var stype = n_json[i]["type"].str
    output &= """
@item $1
  """ % [n_json[i]["name"].str.texize]
    output &= "$1 $2\n" % [(symbols[stype])[1],n_json[i]["code"].str.texize, module]

    if(n_json[i].haskey("code")):
      output &= """
@example
$1
@end example
  """ % n_json[i]["code"].str.texize


    if(n_json[i].haskey("description")):
      writeFile(tmpname,n_json[i]["description"].str)
      output &= execProcess( @["/usr/bin/pandoc","-f","html","-t","texinfo", tmpname].join(" "),
                        @[] ).replace("@node Top","").replace("@top Top","").replace(re"@ref{.*?,(.*?)}","\1")
      tmpname.removeFile()
      discard system.open(tmpname, fmWrite)

    #let id = (symbols[stype])[0]
    symbols[stype][2] = symbols[stype][2] & output

proc Main()=
  var chapters = ""
  var modules : seq[string] = @[]
  var modulei : seq[string] = @[]
  var json_dir = commandLineParams()[0]
  for file in walkDirRec(json_dir ):
    var (mpath, module, ext) = splitFile(file)
    if ext != ".json":
      continue
    var n_json = json.parseFile(file)
    var mod1 = mpath.split(json_dir)
    module = mod1[mod1.len - 1] & "/" & module
    modulei.add(module)
    modules.add("* " & module & "::\n")
    chapters &= "\n@node $1\n" % module
    parse_symb_json(n_json, module)
    for stype in symbols.keys:
      if symbols[stype][2] != "":
         symbols[stype][2] ="""
@chapter $1

@itemize
$2
@end itemize
""" % [symbols[stype][3], symbols[stype][2]]

    chapters &= @[symbols["skConst"][2], symbols["skLet"][2], symbols["skVar"][2], symbols["skType"][2],   symbols["skProc"][2], symbols["skTemplate"][2],symbols["skMacro"][2],symbols["skConverter"][2],symbols["skMethod"][2],symbols["skIterator"][2]].join("\n")

  echo """@settitle The Nim Manual
@ifnottex
@node Top
@top Nim info Manual
@end ifnottex

@menu
"""
  echo modules.join("")
  echo """

* Command and Function Index:: Functions
* Variable Index:: variables
@end menu

hello!
"""
  echo chapters

  echo """
@node Command and Function Index
@unnumbered Command and function index

@printindex fn

@node Variable Index
@unnumbered Variable index

This is not a complete index of variables and faces, only the ones that are
mentioned in the manual.  For a more complete list, use @kbd{M-x
org-customize @key{RET}} and then click yourself through the tree.

@printindex vr

"""
Main()
# Local Variables:
# firestarter: "nim c -d:release nim_texi.nim || notify-send -u low 'nim' 'compile error on nim_texi.nim'"
# End:
