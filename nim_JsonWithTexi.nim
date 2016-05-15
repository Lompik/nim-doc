import compiler/ast
import compiler/commands
import compiler/condsyms
import compiler/extccomp
import compiler/idents
import compiler/importer
import compiler/lexer
import compiler/main
import compiler/msgs
import compiler/nimconf
import compiler/nodejs
import compiler/nversion
import compiler/options
import compiler/platform
import compiler/renderer
import compiler/ropes
import compiler/scriptconfig
import compiler/sempass2
import compiler/service
import compiler/syntaxes
import compiler/typesrenderer
import compiler/wordrecg
import compiler/docgen

import packages/docutils/rstgen
import packages/docutils/rstast
import packages/docutils/rst

import os, osproc, strutils, strtabs, times, json, sequtils

var include_dir*:string=""

proc myFindFile(filename: string): string {.procvar.}=
  let t = joinPath(include_dir,if startsWith(filename,"../"): filename.substr(3) else: filename) ## hardcoded path fix for nim's src
  if existsFile(t): result = t
  else: result = ""

proc strip_string(s:string):string=
  strip(s)


proc isVisible(n: PNode): bool =
  result = false
  if n.kind == nkPostfix:
    if n.len == 2 and n.sons[0].kind == nkIdent:
      var v = n.sons[0].ident
      result = v.id == ord(wStar) or v.id == ord(wMinus)
  elif n.kind == nkSym:
    # we cannot generate code for forwarded symbols here as we have no
    # exception tracking information here. Instead we copy over the comment
    # from the proc header.
    result = {sfExported, sfFromGeneric, sfForward}*n.sym.flags == {sfExported}
  elif n.kind == nkPragmaExpr:
    result = isVisible(n.sons[0])

proc renderRstToTexi*(d: PDoc, n: PRstNode, result: var string)

proc renderAux(d: PDoc, n: PRstNode, result: var string) =
  for i in countup(0, len(n)-1): renderRstToTexi(d, n.sons[i], result)

proc renderAux(d: PDoc, n: PRstNode, frmtA, frmtB, frmtC: string, result: var string) =
  var tmp = ""
  for i in countup(0, len(n)-1): renderRstToTexi(d, n.sons[i], tmp)
  result.addf(frmtC, [tmp])

proc renderAux(d: PDoc, n: PRstNode, frmtA, frmtB: string, result: var string) =
  var tmp = ""
  for i in countup(0, len(n)-1): renderRstToTexi(d, n.sons[i], tmp)
  if d.target != outLatex:
    result.addf(frmtA, [tmp])
  else:
    result.addf(frmtB, [tmp])

proc addTexiChar(dest: var string, c: char) =
  case c
  of '@': add(dest, "@@")
  of '{': add(dest, "@{")
  of '}': add(dest, "@}")
  else: add(dest, c)

proc renderField(d: PDoc, n: PRstNode, result: var string) =
  var b = false
  if d.target == outLatex:
    var fieldname = addNodes(n.sons[0])
    var fieldval = esc(d.target, strip(addNodes(n.sons[1])))
    if cmpIgnoreStyle(fieldname, "author") == 0 or
       cmpIgnoreStyle(fieldname, "authors") == 0:
      if d.meta[metaAuthor].len == 0:
        d.meta[metaAuthor] = fieldval
        b = true
    elif cmpIgnoreStyle(fieldname, "version") == 0:
      if d.meta[metaVersion].len == 0:
        d.meta[metaVersion] = fieldval
        b = true
  if not b:
    renderAux(d, n, "<tr>$1</tr>\n", "$1", result)

proc esc(target: OutputTarget, s: string, splitAfter = -1): string =
  result = ""
  if splitAfter >= 0:
    var partLen = 0
    var j = 0
    while j < len(s):
      var k = nextSplitPoint(s, j)
      if (splitter != " ") or (partLen + k - j + 1 > splitAfter):
        partLen = 0
        add(result, splitter)
      for i in countup(j, k): addTexiChar( result, s[i])
      inc(partLen, k - j + 1)
      j = k + 1
  else:
    for i in countup(0, len(s) - 1): addTexiChar( result, s[i])

proc getName(d: PDoc, n: PNode, splitAfter = -1): string =
  case n.kind
  of nkPostfix: result = getName(d, n.sons[1], splitAfter)
  of nkPragmaExpr: result = getName(d, n.sons[0], splitAfter)
  of nkSym: result = esc(d.target, n.sym.renderDefinitionName, splitAfter)
  of nkIdent: result = esc(d.target, n.ident.s, splitAfter)
  of nkAccQuoted:
    result = esc(d.target, "`")
    for i in 0.. <n.len: result.add(getName(d, n[i], splitAfter))
    result.add esc(d.target, "`")
  else:
    internalError(n.info, "getName()")
    result = ""

proc docgenFindFile(s: string): string {.procvar.} =
  result = options.findFile(s)
  if result.len == 0:
    result = getCurrentDir() / s
    if not existsFile(result): result = ""

proc compilerMsgHandler(filename: string, line, col: int,
                        msgKind: rst.MsgKind, arg: string) {.procvar.} =
  # translate msg kind:
  var k: msgs.TMsgKind
  case msgKind
  of meCannotOpenFile: k = errCannotOpenFile
  of meExpected: k = errXExpected
  of meGridTableNotImplemented: k = errGridTableNotImplemented
  of meNewSectionExpected: k = errNewSectionExpected
  of meGeneralParseError: k = errGeneralParseError
  of meInvalidDirective: k = errInvalidDirectiveX
  of mwRedefinitionOfLabel: k = warnRedefinitionOfLabel
  of mwUnknownSubstitution: k = warnUnknownSubstitutionX
  of mwUnsupportedLanguage: k = warnLanguageXNotSupported
  of mwUnsupportedField: k = warnFieldXNotSupported
  globalError(newLineInfo(filename, line, col), k, arg)

proc parseRst(text, filename: string,
              line, column: int, hasToc: var bool,
              rstOptions: RstParseOptions): PRstNode =
  result = rstParse(text, filename, line, column, hasToc, rstOptions,
                    myFindFile, compilerMsgHandler)


proc renderCodeBlock(d: PDoc, n: PRstNode, result: var string) =
  ## Renders a code block, appending it to `result`.
  ##
  ## If the code block uses the ``number-lines`` option, a table will be
  ## generated with two columns, the first being a list of numbers and the
  ## second the code block itself. The code block can use syntax highlighting,
  ## which depends on the directive argument specified by the rst input, and
  ## may also come from the parser through the internal ``default-language``
  ## option to differentiate between a plain code block and nimrod's code block
  ## extension.
  assert n.kind == rnCodeBlock
  if n.sons[2] == nil: return
  #var params = d.parseCodeBlockParams(n)
  var m = n.sons[2].sons[0]
  assert m.kind == rnLeaf

  renderAux(d, n.sons[2], "a","b","\n@example\n$1\n@end example\n", result)


proc texiColumns(n: PRstNode): string =
  result = ""
  let nsons = len(n.sons[0])
  for i in countup(1, nsons): add(result, " " & $(1.0/(nsons.toFloat)))

proc texColumns(n: PRstNode): string =
  result = ""
  for i in countup(1, len(n)): add(result, "|X")

proc disp(target: OutputTarget, xml, tex: string): string =
  if target != outLatex: result = xml
  else: result = tex

proc dispF(target: OutputTarget, xml, tex: string,
           args: varargs[string]): string =
  if target != outLatex: result = xml % args
  else: result = tex % args

proc dispA(target: OutputTarget, dest: var string,
           xml, tex: string, texi: string, args: varargs[string]) =
  case target:
  of outHtml: addf(dest, xml, args)
  else: addf(dest, texi, args)

proc dispA(target: OutputTarget, dest: var string,
           xml, tex: string, args: varargs[string]) =
  if target != outLatex: addf(dest, xml, args)
  else: addf(dest, tex, args)


proc renderHeadline(d: PDoc, n: PRstNode, result: var string) =
  discard
proc renderOverline(d: PDoc, n: PRstNode, result: var string) =
  discard

type TocEntry = object
    n*: PRstNode
    refname*, header*: string

proc renderTocEntries*(d: var RstGenerator, j: var int, lvl: int,
                       result: var string) =
  discard
proc renderImage(d: PDoc, n: PRstNode, result: var string) =
  template valid(s): expr =
    s.len > 0 and allCharsInSet(s, {'.','/',':','%','_','\\','\128'..'\xFF'} +
                                   Digits + Letters + WhiteSpace)

  var options = ""
  var s = getFieldValue(n, "scale")
  if s.valid: dispA(d.target, options, " scale=\"$1\"", " scale=$1", [strip(s)])

  s = getFieldValue(n, "height")
  if s.valid: dispA(d.target, options, " height=\"$1\"", " height=$1", [strip(s)])

  s = getFieldValue(n, "width")
  if s.valid: dispA(d.target, options, " width=\"$1\"", " width=$1", [strip(s)])

  s = getFieldValue(n, "alt")
  if s.valid: dispA(d.target, options, " alt=\"$1\"", "", [strip(s)])

  s = getFieldValue(n, "align")
  if s.valid: dispA(d.target, options, " align=\"$1\"", "", [strip(s)])

  if options.len > 0: options = dispF(d.target, "$1", "[$1]", [options])

  let arg = getArgument(n)
  if arg.valid:
    dispA(d.target, result, "<img src=\"$1\"$2 />", "\\includegraphics$2{$1}",
          [arg, options])
  if len(n) >= 3: renderRstToTexi(d, n.sons[2], result)

proc renderSmiley(d: PDoc, n: PRstNode, result: var string) =
  dispA(d.target, result,
    """<img src="$1" width="15"
        height="17" hspace="2" vspace="2" class="smiley" />""",
    "\\includegraphics{$1}",
    [d.config.getOrDefault"doc.smiley_format" % n.text])

proc renderContainer(d: PDoc, n: PRstNode, result: var string) =
  discard

proc renderIndexTerm(d: PDoc, n: PRstNode, result: var string) =
  discard

proc renderRstToTexi(d: PDoc, n: PRstNode, result: var string) =
  if n == nil: return
  case n.kind
  of rnInner: renderAux(d, n, result)
  of rnHeadline: renderHeadline(d, n, result)
  of rnOverline: renderOverline(d, n, result)
  of rnTransition: renderAux(d, n, "<hr />\n", "\\hrule\n","\n",  result)
  of rnParagraph: renderAux(d, n, "<p>$1</p>\n", "$1\n\n", "$1\n\n", result)
  of rnBulletList:
    renderAux(d, n, "<ul class=\"simple\">$1</ul>\n",
                    "\\begin{itemize}$1\\end{itemize}\n", "\n@itemize \n $1 \n@end itemize\n", result)
  of rnBulletItem, rnEnumItem:
    renderAux(d, n, "<li>$1</li>\n", "\\item $1\n","@item $1\n", result)
  of rnEnumList:
    renderAux(d, n, "<ol class=\"simple\">$1</ol>\n",
                    "\\begin{enumerate}$1\\end{enumerate}\n", "\n@itemize \n $1 \n@end itemize\n",result)
  of rnDefList:
    renderAux(d, n, "<dl class=\"docutils\">$1</dl>\n",
                       "\\begin{description}$1\\end{description}\n","\n@itemize \n $1 \n@end itemize\n", result)
  of rnDefItem: renderAux(d, n, result)
  of rnDefName: renderAux(d, n, "<dt>$1</dt>\n", "\\item[$1] ", "@item $1: ", result)
  of rnDefBody: renderAux(d, n, "<dd>$1</dd>\n", "$1\n", "$1\n", result)
  of rnFieldList:
    var tmp = ""
    for i in countup(0, len(n) - 1):
      renderRstToTexi(d, n.sons[i], tmp)
    if tmp.len != 0:
      dispA(d.target, result,
          "<table class=\"docinfo\" frame=\"void\" rules=\"none\">" &
          "<col class=\"docinfo-name\" />" &
          "<col class=\"docinfo-content\" />" &
          "<tbody valign=\"top\">$1" &
          "</tbody></table>",
          "\\begin{description}$1\\end{description}\n","\n@itemize \n $1 \n@end itemize\n",
          [tmp])
  of rnField: renderField(d, n, result)
  of rnFieldName:
    renderAux(d, n, "<th class=\"docinfo-name\">$1:</th>",
                    "\\item[$1:]","@item $1: ", result)
  of rnFieldBody:
    renderAux(d, n, "<td>$1</td>", " $1\n", "$1 \n", result)
  of rnIndex:
    renderRstToTexi(d, n.sons[2], result)
  of rnOptionList:
    renderAux(d, n, "<table frame=\"void\">$1</table>",
              "\\begin{description}\n$1\\end{description}\n", "\n@itemize \n $1 \n@end itemize\n", result)
  of rnOptionListItem:
    renderAux(d, n, "<tr>$1</tr>\n", "$1", "$1 \n", result)
  of rnOptionGroup:
    renderAux(d, n, "<th align=\"left\">$1</th>", "\\item[$1]", "@item $1: ", result)
  of rnDescription:
    renderAux(d, n, "<td align=\"left\">$1</td>\n", " $1\n", result)
  of rnOption, rnOptionString, rnOptionArgument:
    doAssert false, "renderRstToTexi"
  of rnLiteralBlock:
    renderAux(d, n, "<pre>$1</pre>\n",
                    "\\begin{rstpre}\n$1\n\\end{rstpre}\n", "\n@verbatim\n$1\n@end verbatim\n", result)
  of rnQuotedLiteralBlock:
    doAssert false, "renderRstToTexi"
  of rnLineBlock:
    renderAux(d, n, "<p>$1</p>", "$1\n\n", result)
  of rnLineBlockItem:
    renderAux(d, n, "$1<br />", "$1\\\\\n", result)
  of rnBlockQuote:
    renderAux(d, n, "<blockquote><p>$1</p></blockquote>\n",
                    "\\begin{quote}$1\\end{quote}\n", "\n@quotation $1 \n@end quotation\n", result)
  of rnTable, rnGridTable:
    renderAux(d, n,
      "<table border=\"1\" class=\"docutils\">$1</table>",
      "\\begin{table}\\begin{rsttab}{" &
        texColumns(n) & "|}\n\\hline\n$1\\end{rsttab}\\end{table}", "\n@multitable @columnfractions " &
        texiColumns(n) & "\n$1"& "\n\n@end multitable\n", result)
  of rnTableRow:
    if len(n) >= 1:
      if d.target == outLatex:
        #var tmp = ""
        result.add("@item ")
        renderRstToTexi(d, n.sons[0], result)
        for i in countup(1, len(n) - 1):
          result.add("\n@tab ")
          renderRstToTexi(d, n.sons[i], result)
          result.add("\n")
      else:
        result.add("<tr>")
        renderAux(d, n, result)
        result.add("</tr>\n")
  of rnTableDataCell:
    renderAux(d, n, "<td>$1</td>", "$1", result)
  of rnTableHeaderCell:
    renderAux(d, n, "<th>$1</th>", "\\textbf{$1}", "@b{$1}", result)
  of rnLabel:
    doAssert false, "renderRstToTexi" # used for footnotes and other
  of rnFootnote:
    doAssert false, "renderRstToTexi" # a footnote
  of rnCitation:
    doAssert false, "renderRstToTexi" # similar to footnote
  of rnRef:
    var tmp = ""
    renderAux(d, n, tmp)
    dispA(d.target, result,
      "<a class=\"reference external\" href=\"#$2\">$1</a>",
      "$1\\ref{$2}", "@uref{$2, $1}", [tmp, rstnodeToRefname(n)])
  of rnStandaloneHyperlink:
    renderAux(d, n,
      "<a class=\"reference external\" href=\"$1\">$1</a>",
      "\\href{$1}{$1}", "@uref{$1, $1}", result)
  of rnHyperlink:
    var tmp0 = ""
    var tmp1 = ""
    renderRstToTexi(d, n.sons[0], tmp0)
    renderRstToTexi(d, n.sons[1], tmp1)
    dispA(d.target, result,
      "<a class=\"reference external\" href=\"$2\">$1</a>",
      "\\href{$2}{$1}", "@uref{$2, $1}", [tmp0, tmp1])
  of rnDirArg, rnRaw: renderAux(d, n, result)
  of rnRawHtml:
    if d.target != outLatex:
      result.add addNodes(lastSon(n))
  of rnRawLatex:
    if d.target == outLatex:
      result.add addNodes(lastSon(n))

  of rnImage, rnFigure: renderImage(d, n, result)
  of rnCodeBlock: renderCodeBlock(d, n, result)
  of rnContainer: renderContainer(d, n, result)
  of rnSubstitutionReferences, rnSubstitutionDef:
    renderAux(d, n, "|$1|", "|$1|", result)
  of rnDirective:
    renderAux(d, n, "", "", result)
  of rnGeneralRole:
    var tmp0 = ""
    var tmp1 = ""
    renderRstToTexi(d, n.sons[0], tmp0)
    renderRstToTexi(d, n.sons[1], tmp1)
    dispA(d.target, result, "<span class=\"$2\">$1</span>", "\\span$2{$1}",
          [tmp0, tmp1])
  of rnSub: renderAux(d, n, "<sub>$1</sub>", "\\rstsub{$1}", result)
  of rnSup: renderAux(d, n, "<sup>$1</sup>", "\\rstsup{$1}", result)
  of rnEmphasis: renderAux(d, n, "<em>$1</em>", "\\emph{$1}", "@emph{$1}", result)
  of rnStrongEmphasis:
    renderAux(d, n, "<strong>$1</strong>", "\\textbf{$1}", "@strong{$1}", result)
  of rnTripleEmphasis:
    renderAux(d, n, "<strong><em>$1</em></strong>",
                    "\\textbf{emph{$1}}", "@strong{@emph{$1}}", result)
  of rnInterpretedText:
    renderAux(d, n, "<cite>$1</cite>", "\\emph{$1}", "@emph{$1}", result)
  of rnIdx:
    renderIndexTerm(d, n, result)
  of rnInlineLiteral:
    renderAux(d, n,
      "<tt class=\"docutils literal\"><span class=\"pre\">$1</span></tt>",
      "\\texttt{$1}", "@code{$1}", result)
  of rnSmiley: renderSmiley(d, n, result)
  of rnLeaf: result.add(esc(d.target, n.text))
  of rnContents: d.hasToc = true
  of rnTitle:
    d.meta[metaTitle] = ""
    renderRstToTexi(d, n.sons[0], d.meta[metaTitle])


proc genComment(d: PDoc, n: PNode): string =
  result = ""
  var dummyHasToc: bool
  if n.comment != nil:
    renderRstToTexi(d, parseRst(n.comment, toFilename(n.info),
                               toLinenumber(n.info), toColumn(n.info),
                               dummyHasToc, d.options), result)

proc genRecComment(d: PDoc, n: PNode): Rope =
  if n == nil: return nil
  result = genComment(d, n).rope
  if result == nil:
    if n.kind notin {nkEmpty..nkNilLit, nkEnumTy}:
      for i in countup(0, len(n)-1):
        result = genRecComment(d, n.sons[i])
        if result != nil: return
  else:
    n.comment = nil

proc genJSONItem(d: PDoc, n, nameNode: PNode, k: TSymKind): JsonNode =
  if not isVisible(nameNode): return
  var
    name = getName(d, nameNode)
    comm = $genRecComment(d, n)
    r: TSrcGen

  initTokRender(r, n, {renderNoBody, renderNoComments, renderDocComments})

  result = %{ "name": %name, "type": %($k) }

  if comm != nil and comm != "":
    result["description"] = %comm
  if r.buf != nil:
    if r.buf.count("\L") < 3:
      result["code"] = %(r.buf.split("\L").map(strip_string).join("").replace(":", "꞉"))
    else:
      result["code"] = %(r.buf)

proc checkForFalse(n: PNode): bool =
  result = n.kind == nkIdent and identEq(n.ident, "false")

proc generateJson(d: PDoc, n: PNode, jArray: JsonNode = nil): JsonNode =
  case n.kind
  of nkCommentStmt:
    if n.comment != nil:
      result = %{ "moduledesc": %genComment(d,n) }
  of nkProcDef:
    when useEffectSystem: documentRaises(n)
    result = genJSONItem(d, n, n.sons[namePos], skProc)
  of nkMethodDef:
    when useEffectSystem: documentRaises(n)
    result = genJSONItem(d, n, n.sons[namePos], skMethod)
  of nkIteratorDef:
    when useEffectSystem: documentRaises(n)
    result = genJSONItem(d, n, n.sons[namePos], skIterator)
  of nkMacroDef:
    result = genJSONItem(d, n, n.sons[namePos], skMacro)
  of nkTemplateDef:
    result = genJSONItem(d, n, n.sons[namePos], skTemplate)
  of nkConverterDef:
    when useEffectSystem: documentRaises(n)
    result = genJSONItem(d, n, n.sons[namePos], skConverter)
  of nkTypeSection, nkVarSection, nkLetSection, nkConstSection:
    for i in countup(0, sonsLen(n) - 1):
      if n.sons[i].kind != nkCommentStmt:
        # order is always 'type var let const':
        result = genJSONItem(d, n.sons[i], n.sons[i].sons[0],
                succ(skType, ord(n.kind)-ord(nkTypeSection)))
  of nkStmtList:
    result = if jArray != nil: jArray else: newJArray()

    for i in countup(0, sonsLen(n) - 1):
      var r = generateJson(d, n.sons[i], result)
      if r != nil:
        result.add(r)

  of nkWhenStmt:
    # generate documentation for the first branch only:
    if not checkForFalse(n.sons[0].sons[0]) and jArray != nil:
      discard generateJson(d, lastSon(n.sons[0]), jArray)
  else: discard

const
  messages: array [MsgKind, string] = [
    meCannotOpenFile: "cannot open '$1'",
    meExpected: "'$1' expected",
    meGridTableNotImplemented: "grid table is not implemented",
    meNewSectionExpected: "new section expected",
    meGeneralParseError: "general parse error",
    meInvalidDirective: "invalid directive: '$1'",
    mwRedefinitionOfLabel: "redefinition of label '$1'",
    mwUnknownSubstitution: "unknown substitution '$1'",
    mwUnsupportedLanguage: "language '$1' not supported",
    mwUnsupportedField: "field '$1' not supported"
  ]

proc msgHandler(filename: string, line, col: int, msgkind: MsgKind,
                        arg: string) {.procvar.} =
  let mc = msgkind.whichMsgClass
  let a = messages[msgkind] % arg
  let message = "$1($2, $3) $4: $5" % [filename, $line, $col, $mc, a]
  if mc == mcError:
    stderr.writeLine message
    stderr.writeLine "Error parsing \"" & filename & "\". Continuing."
    raise newException(EParseError, message)
  else: writeLine(stdout, message)

proc get_json():JsonNode=
  var ast = parseFile(gProjectMainIdx)
  if ast == nil: return
  var d : PDoc
  new(d)
  initRstGenerator(g=d[], outLatex,
                   config=options.gConfigVars, filename=gProjectFull, options={roSupportRawDirective},
                   cast[FindFileHandler](myFindFile), cast[MsgHandler](msgHandler))

  d.hasToc = false
  result = generateJson(d, ast)


proc parseNim*(file: string): JsonNode=
  if file != "":
    gCmd= cmdDoc
    try:
      gProjectFull = canonicalizePath(unixToNativePath(file))
    except OSError:
      gProjectFull = gProjectName
    let p = splitFile(gProjectFull)
    gProjectPath = p.dir
    gProjectName = p.name
    if gProjectFull.len == 0:
      fatal(gCmdLineInfo, errCommandExpectsFilename)
    gProjectMainIdx = addFileExt(gProjectFull, NimExt).fileInfoIdx
    result = get_json()

if (isMainModule):
  echo pretty(parseNim(commandLineParams()[0]))
