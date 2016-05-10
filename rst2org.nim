import options

#import rst, rstast
import strutils
import strtabs

import packages/docutils/rstgen
import packages/docutils/rstast
import packages/docutils/rst




type
  RenderContext {.pure.} = object
    indent: int
    verbatim: int
{.deprecated: [TRenderContext: RenderContext].}

proc renderRstToOrg(d: var RenderContext, n: PRstNode,
                    result: var string) {.gcsafe.}

proc renderRstSons(d: var RenderContext, n: PRstNode, result: var string) =
  for i in countup(0, len(n) - 1):
    renderRstToOrg(d, n.sons[i], result)

proc renderRstToOrg(d: var RenderContext, n: PRstNode, result: var string) =
  # this is needed for the index generation; it may also be useful for
  # debugging, but most code is already debugged...
  const
    lvlToChar: array[0..8, char] = ['!', '=', '-', '~', '`', '<', '*', '|', '+']
  if n == nil: return
  var ind = spaces(d.indent)

  case n.kind
  of rnInner:
    renderRstSons(d, n, result)
  of rnHeadline:
    result.add("\n" & repeat("*",n.level) & " " )
    result.add(ind)

    let oldLen = result.len
    renderRstSons(d, n, result)
    # let headlineLen = result.len - oldLen

    # result.add("\n")
    # result.add(ind)
    # result.add repeat(lvlToChar[n.level], headlineLen)
  of rnOverline:
    result.add("\n")
    result.add(ind)

    var headline = ""
    renderRstSons(d, n, headline)

    let lvl = repeat(lvlToChar[n.level], headline.len - d.indent)
    result.add(lvl)
    result.add("\n")
    result.add(headline)

    result.add("\n")
    result.add(ind)
    result.add(lvl)
  of rnTransition:
    result.add("\n\n")
    result.add(ind)
    result.add repeat('-', 78-d.indent)
    result.add("\n\n")
  of rnParagraph:
    result.add("\n\n")
    result.add(ind)
    renderRstSons(d, n, result)
  of rnBulletItem:
    inc(d.indent, 2)
    var tmp = ""
    renderRstSons(d, n, tmp)
    if tmp.len > 0:
      result.add("\n")
      result.add(ind)
      result.add("- ")
      result.add(tmp)
    dec(d.indent, 2)
  of rnEnumItem:
    inc(d.indent, 4)
    var tmp = ""
    renderRstSons(d, n, tmp)
    if tmp.len > 0:
      result.add("\n")
      result.add(ind)
      result.add("- ")
      result.add(tmp)
    dec(d.indent, 4)
  of rnOptionList, rnFieldList, rnDefList, rnDefItem, rnLineBlock, rnFieldName,
     rnFieldBody, rnStandaloneHyperlink, rnBulletList, rnEnumList:
    renderRstSons(d, n, result)
  of rnDefName:
    result.add("\n\n")
    result.add(ind)
    renderRstSons(d, n, result)
  of rnDefBody:
    inc(d.indent, 2)
    if n.sons[0].kind != rnBulletList:
      result.add("\n")
      result.add(ind)
      result.add("  ")
    renderRstSons(d, n, result)
    dec(d.indent, 2)
  of rnField:
    var tmp = ""
    renderRstToOrg(d, n.sons[0], tmp)

    var L = max(tmp.len + 3, 30)
    inc(d.indent, L)

    result.add "\n"
    result.add ind
    result.add ':'
    result.add tmp
    result.add ':'
    result.add spaces(L - tmp.len - 2)
    renderRstToOrg(d, n.sons[1], result)

    dec(d.indent, L)
  of rnLineBlockItem:
    result.add("\n")
    result.add(ind)
    result.add("| ")
    renderRstSons(d, n, result)
  of rnBlockQuote:
    inc(d.indent, 2)
    renderRstSons(d, n, result)
    dec(d.indent, 2)
  of rnRef:
    result.add("`")
    renderRstSons(d, n, result)
    result.add("`_")
  of rnHyperlink:
    result.add("[[")
    renderRstToOrg(d, n.sons[1], result)
    result.add("][")
    renderRstToOrg(d, n.sons[0], result)
    result.add("]]")
  of rnGeneralRole:
    result.add('`')
    renderRstToOrg(d, n.sons[0],result)
    result.add("`:")
    renderRstToOrg(d, n.sons[1],result)
    result.add(':')
  of rnSub:
    result.add('`')
    renderRstSons(d, n, result)
    result.add("`:sub:")
  of rnSup:
    result.add('`')
    renderRstSons(d, n, result)
    result.add("`:sup:")
  of rnIdx:
    result.add('`')
    renderRstSons(d, n, result)
    result.add("`:idx:")
  of rnEmphasis:
    result.add("*")
    renderRstSons(d, n, result)
    result.add("*")
  of rnStrongEmphasis:
    result.add("_")
    renderRstSons(d, n, result)
    result.add("_")
  of rnTripleEmphasis:
    result.add("***")
    renderRstSons(d, n, result)
    result.add("***")
  of rnInterpretedText:
    result.add('`')
    renderRstSons(d, n, result)
    result.add('`')
  of rnInlineLiteral:
    inc(d.verbatim)
    result.add("~")
    renderRstSons(d, n, result)
    result.add("~")
    dec(d.verbatim)
  of rnSmiley:
    result.add(n.text)
  of rnLeaf:
    if d.verbatim == 0 and n.text == "\\":
      result.add("\\\\") # XXX: escape more special characters!
    else:
      result.add(n.text)
  of rnIndex:
    result.add("\n\n")
    result.add(ind)
    result.add(".. index::\n")

    inc(d.indent, 3)
    if n.sons[2] != nil: renderRstSons(d, n.sons[2], result)
    dec(d.indent, 3)
  of rnContents:
    result.add("\n\n")
    result.add(ind)
    result.add(".. contents::")
  of rnCodeBlock:
    result.add("\n\n")
    result.add("#+BEGIN_SRC ")
    if len(n.sons)> 0 and len(n.sons[0].sons) > 0:
      result.add(n.sons[0].sons[0].text & "\n")
    if len(n.sons)>= 2:
      inc(d.indent, 4)
      renderRstSons(d, n.sons[2], result)
      dec(d.indent, 4)
    result.add("\n")
    result.add("#+END_SRC\n")
  of rnLiteralBlock:
    if len(n.sons)>= 2 and n.sons[2] != nil: renderRstSons(d, n.sons[2], result)
  of rnImage:
    result.add("\n")
    result.add("[[file:")
    var i=0
    while i<len(n.sons):
      result.add($n.sons[0].sons[i].text)
      i=i+1
    result.add("]]")

  else:
    result.add("Error: cannot render: " & $n.kind)

proc renderRstToOrg*(n: PRstNode, result: var string) =
  ## renders `n` into its string representation and appends to `result`.
  var d: RenderContext
  renderRstToOrg(d, n, result)

proc myFindFile(filename: string): string =
  # we don't find any files in online mode:
  result = ""
var dummyHasToc = false

const filen = "input"
when(defined(debug)):
  var d: RstGenerator
  initRstGenerator(d, outHtml,newStringTable(modeStyleInsensitive),  filen, {}, cast[FindFileHandler](myFindFile), cast[MsgHandler](defaultMsgHandler))
  var rstP = rst.rstParse("""
=======
Header1
=======

Header2
=======

Header3
+++++++

*Hello* **world**!

`Python home page <http://www.python.org>`_

.. code-block:: nim
  type
    Table[Key, Value] = object
      keys: seq[Key]
      values: seq[Value]
      when not (Key is string): # nil value for strings used for optimization
        deletedKeys: seq[bool]

:Authors:
  Hello

.. image:: test.png
""", filen, 0, 1, dummyHasToc, {})
  var resultP = ""
  var d1: RenderContext
  renderRstToOrg(d1, rstP, resultP)
  echo $resultP

import nre
import os
import tables
import osproc

let includes = re"\.\. include:: (?<filename>\S*)"
var data =newTable[string,string]()
var included:seq[string] = @[]
var notParsed: seq[string] = @[]

proc replace_included(match:RegexMatch): string=
  var file = match.captures["filename"]
  included.add(file )
  try:
    result = readFile( "/home/lompik/repos/nim-0.13.0/doc/".joinpath( file))
  except:
    echo "could not open file : " & file
    result = "could not open file : " & file

when(isMainModule):

  let arguments = commandLineParams()

  var test=""
  for file in arguments:
    try:
      data [ file] =  readFile(file)
    except:
      echo "Cannot read " & file

  var resultP = ""
  var rstP:PRstNode
  for file in data.keys:
    data[file] = data[file].replace(includes, replace_included)

  #for fileInc in test.find.match(test):

  for file in data.keys:
    try:
      discard rst.rstParse(data[file], filen, 0, 1, dummyHasToc, {})
      test &= "\n" & data[file] & "\n"
    except:
      notParsed.add(file)
      echo "Cannot Parse: " & file

  try:
     rstP =rst.rstParse(test, filen, 0, 1, dummyHasToc, {})
  except:
    echo "Cannot Parse: " #& file
    quit 0
  var d1: RenderContext
  renderRstToOrg(d1, rstP, resultP)
  echo "------" & "\n" & resultP

  for file in notParsed:
      echo execProcess( @[joinPath(os.getAppdir(),"pandoc_proc"), file].join(" "),@[] )

# Local Variables:
# firestarter: "nim c -d:release %f || notify-send -u low 'nim' 'compile error on %f'"
# End:


# All unique token of /usr/share/nim/doc/manual/*
## rnCodeBlock -> begin_src blocks
## rnEmphasis -> **
## rnEnumItem -> -
## rnEnumList ->
## rnHeadline
## rnIdx
## rnInlineLiteral
## rnInner
## rnLeaf
## rnLeafrnInner
## rnParagraph
## rnRef
## rnStrongEmphasis -> underline
