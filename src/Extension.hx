import neohscript.AstTools;
import neohscript.Analyzer;
import neohscript.Diagnoser;
import neohscript.Doc;
import neohscript.Expr;
import neohscript.Formatter;
import neohscript.DocGen;
import neohscript.LineMap;
import neohscript.Modules;
import neohscript.Project;
import neohscript.Symbols;
import neohscript.Ty;
import neohscript.TyTools;
import neohscript.TypeEnv;
import vscode.*;

class Extension {
	static inline var LANG = "neohscript";
	static final DEFAULT_GLOBALS = ["print", "Math", "Std"];
	static final KEYWORDS = [
		"var",
		"final",
		"function",
		"if",
		"else",
		"while",
		"do",
		"for",
		"in",
		"break",
		"continue",
		"return",
		"new",
		"throw",
		"try",
		"catch",
		"switch",
		"case",
		"default",
		"true",
		"false",
		"null",
		"import",
		"using",
		"class",
		"interface",
		"enum",
		"typedef",
		"extends",
		"implements",
		"public",
		"private",
		"static",
		"inline",
		"override"
	];
	static final BASIC_TYPES = ["Int", "Float", "Bool", "String", "Void", "Dynamic", "Array", "Map", "Null"];
	static final TOKEN_TYPES = [
		"namespace",
		"class",
		"enum",
		"interface",
		"type",
		"typeParameter",
		"parameter",
		"variable",
		"property",
		"enumMember",
		"method",
		"function"
	];
	static final TOKEN_MODS = ["declaration", "readonly", "static", "deprecated"];

	static final SNIPPETS:Array<{label:String, detail:String, body:String}> = [
		{label: "if", detail: "if (...) { }", body: "if (${1:cond}) {\n\t$0\n}"},
		{label: "ifelse", detail: "if / else", body: "if (${1:cond}) {\n\t$2\n} else {\n\t$0\n}"},
		{label: "for", detail: "for (i in a...b)", body: "for (${1:i} in ${2:0}...${3:10}) {\n\t$0\n}"},
		{label: "foreach", detail: "for (x in iterable)", body: "for (${1:item} in ${2:items}) {\n\t$0\n}"},
		{label: "forkv", detail: "for (k => v in map)", body: "for (${1:k} => ${2:v} in ${3:map}) {\n\t$0\n}"},
		{label: "while", detail: "while (...) { }", body: "while (${1:cond}) {\n\t$0\n}"},
		{label: "function", detail: "function name(args) { }", body: "function ${1:name}(${2}) {\n\t$0\n}"},
		{label: "genericfunction", detail: "function name<T>(args) { }", body: "function ${1:name}<${2:T}>(${3:x}:${2:T}):${2:T} {\n\t$0\n}"},
		{
			label: "docfunction",
			detail: "documented function",
			body: "/**\n * ${1:Description}\n * @param {${2:Int}} ${3:arg} ${4:Description}\n * @returns {${5:Void}} ${6:Description}\n */\nfunction ${7:name}(${3}) {\n\t$0\n}"
		},
		{label: "lambda", detail: "(args) -> expr", body: "(${1:x}) -> ${0:x}"},
		{label: "switch", detail: "switch / case / default", body: "switch (${1:value}) {\n\tcase ${2:1}:\n\t\t$0\n\tdefault:\n}"},
		{label: "try", detail: "try / catch", body: "try {\n\t$1\n} catch (${2:e}) {\n\t$0\n}"},
		{label: "var", detail: "var name:Type = value", body: "var ${1:name}${2::Type} = ${0:value};"},
		{label: "class", detail: "class declaration", body: "class ${1:Name} {\n\tpublic function new(${2}) {\n\t\t$0\n\t}\n}"},
		{label: "interface", detail: "interface declaration", body: "interface ${1:Name} {\n\tfunction ${2:method}():${3:Void};\n}"},
		{label: "enum", detail: "enum declaration", body: "enum ${1:Name} {\n\t${2:First};\n\t${3:Second}(${4:value}:${5:Int});\n}"},
		{label: "typedef", detail: "typedef declaration", body: "typedef ${1:Name} = {\n\t${2:field}:${3:Int}\n};"},
		{label: "import", detail: "import module", body: "import ${1:pack.Module};"}
	];

	static final CHAIN = ~/([A-Za-z_]\w*(?:\s*\??\.\s*[A-Za-z_]\w*)*)\s*\??\.\s*\w*$/;
	static final ACCESS_CHAIN = ~/^([A-Za-z_]\w*(?:\s*\??\.\s*[A-Za-z_]\w*)*)\s*\??\.\s*\w*$/;
	static final MEMBER_ACCESS = ~/[\w)\]]\s*(\.|\?\.)\s*\w*$/;
	static final TYPE_ANNOT = ~/(?:\b(?:var|final)\s+\w+|[(,]\s*\??\w+|\))\s*:\s*[\w.]*$/;
	static final NEW_CTX = ~/\bnew\s+[\w.]*$/;
	static final IMPORT_CTX = ~/^\s*(import|using)\s+([\w.]*)$/;
	static final CALLEE = ~/([A-Za-z_]\w*(?:\s*\??\.\s*[A-Za-z_]\w*)*)\s*$/;
	static final NEW_BEFORE = ~/\bnew\s+$/;
	static final IDENT = ~/^[A-Za-z_][A-Za-z0-9_]*$/;

	static var diagnostics:DiagnosticCollection;
	static var definitionDiagnostics:DiagnosticCollection;
	static var host:MemoryHost = new MemoryHost();
	static var project:Project;
	static final diagnoses = new Map<String, Diagnosis>();
	static var output:OutputChannel;

	static function main() {}

	@:expose("activate")
	static function activate(context:ExtensionContext) {
		var sub = context.subscriptions;
		project = new Project(host);
		diagnostics = Vscode.languages.createDiagnosticCollection(LANG);
		definitionDiagnostics = Vscode.languages.createDiagnosticCollection(LANG + "-definitions");
		sub.push(diagnostics);
		sub.push(definitionDiagnostics);
		applySettings();

		sub.push(Vscode.workspace.onDidOpenTextDocument(d -> refreshOne(d)));
		sub.push(Vscode.workspace.onDidChangeTextDocument(e -> {
			refreshOne(e.document);
			refreshAll();
		}));
		sub.push(Vscode.workspace.onDidCloseTextDocument(function(d) {
			diagnoses.remove(d.uri.toString());
			diagnostics.delete(d.uri);
		}));
		sub.push(Vscode.workspace.onDidChangeConfiguration(function(e) {
			if (e.affectsConfiguration(LANG)) {
				applySettings();
				loadDefinitions();
				indexWorkspace();
			}
		}));

		var jsonWatcher = Vscode.workspace.createFileSystemWatcher("**/*.json");
		sub.push(jsonWatcher);
		sub.push(jsonWatcher.onDidChange(onJsonChanged));
		sub.push(jsonWatcher.onDidCreate(onJsonChanged));
		sub.push(jsonWatcher.onDidDelete(onJsonChanged));

		var srcWatcher = Vscode.workspace.createFileSystemWatcher("**/*.hxs");
		sub.push(srcWatcher);
		sub.push(srcWatcher.onDidCreate(onSourceChanged));
		sub.push(srcWatcher.onDidChange(onSourceChanged));
		sub.push(srcWatcher.onDidDelete(function(u) {
			host.remove(u.toString());
			project.invalidateAll();
			refreshAll();
		}));

		sub.push(Vscode.languages.registerHoverProvider(LANG, {provideHover: provideHover}));
		sub.push(Vscode.languages.registerDefinitionProvider(LANG, {provideDefinition: provideDefinition}));
		sub.push(Vscode.languages.registerReferenceProvider(LANG, {provideReferences: provideReferences}));
		sub.push(Vscode.languages.registerRenameProvider(LANG, {provideRenameEdits: provideRename, prepareRename: prepareRename}));
		sub.push(Vscode.languages.registerDocumentHighlightProvider(LANG, {provideDocumentHighlights: provideHighlights}));
		sub.push(Vscode.languages.registerDocumentSymbolProvider(LANG, {provideDocumentSymbols: provideSymbols}));
		sub.push(Vscode.languages.registerWorkspaceSymbolProvider({provideWorkspaceSymbols: provideWorkspaceSymbols}));
		sub.push(Vscode.languages.registerCompletionItemProvider(LANG, {provideCompletionItems: provideCompletion}));
		sub.push(Vscode.languages.registerSignatureHelpProvider(LANG, {provideSignatureHelp: provideSignature}, "(", ","));
		sub.push(Vscode.languages.registerFoldingRangeProvider(LANG, {provideFoldingRanges: provideFolding}));
		sub.push(Vscode.languages.registerInlayHintsProvider(LANG, {provideInlayHints: provideInlayHints, resolveInlayHint: (h, _) -> h}));
		sub.push(Vscode.languages.registerCodeActionsProvider(LANG, {provideCodeActions: provideCodeActions}));
		sub.push(Vscode.languages.registerDocumentFormattingEditProvider(LANG, {provideDocumentFormattingEdits: provideFormatting}));
		var legend = new SemanticTokensLegend(TOKEN_TYPES, TOKEN_MODS);
		sub.push(Vscode.languages.registerDocumentSemanticTokensProvider(LANG, {provideDocumentSemanticTokens: provideSemanticTokens}, legend));

		sub.push(Vscode.commands.registerCommand("neohscript.reloadDefinitions", function() {
			loadDefinitions();
			indexWorkspace();
			return null;
		}));
		sub.push(Vscode.commands.registerCommand("neohscript.generateDocs", generateDocs));

		for (d in Vscode.workspace.textDocuments)
			refreshOne(d);
		loadDefinitions();
		indexWorkspace();
	}

	static function cfg<T>(key:String, def:T):T {
		var v:Null<T> = Vscode.workspace.getConfiguration(LANG).get(key);
		return v != null ? v : def;
	}

	static function roots():Array<String>
		return cfg("sourceRoots", [""]);

	static function applySettings():Void {
		project.globals = cfg("globals", DEFAULT_GLOBALS);
		project.defines = cfg("defines", []);
		project.strictness = switch (cfg("analysis.strictness", "basic")) {
			case "off": SOff;
			case "strict": SStrict;
			default: SBasic;
		}
		project.invalidateAll();
	}

	static function modulePath(doc:TextDocument):Null<String>
		return MemoryHost.modulePathOf(Vscode.workspace.asRelativePath(doc.uri, false), roots());

	static function toUri(file:String):Uri
		return file.indexOf("://") > 0 ? Uri.parse(file) : Uri.file(file);

	static function textOfUri(uri:String):Null<String> {
		for (d in Vscode.workspace.textDocuments)
			if (d.uri.toString() == uri)
				return d.getText();
		var m = host.moduleOfUri(uri);
		if (m == null)
			return null;
		var src = host.read(m);
		return src == null ? null : src.text;
	}

	static function rangeIn(text:String, p:neohscript.Pos):Range {
		var r = new LineMap(text).range(p);
		return new Range(new Position(r.start.line, r.start.character), new Position(r.end.line, r.end.character));
	}

	static function range(doc:TextDocument, p:neohscript.Pos):Range
		return new Range(doc.positionAt(p.min), doc.positionAt(p.max));

	static function markdown(code:Null<String>, doc:Null<Doc>, includeParams:Bool = true):MarkdownString {
		var md = new MarkdownString();
		if (code != null)
			md.appendCodeblock(code, LANG);
		if (doc != null) {
			var body = DocTools.toMarkdown(doc, includeParams);
			if (body != "")
				md.appendMarkdown((code != null ? "\n\n" : "") + body);
		}
		return md;
	}

	static function syncDoc(doc:TextDocument):Void {
		var mp = modulePath(doc);
		if (mp == null)
			return;
		var text = doc.getText();
		var old = host.read(mp);
		if (old == null || old.text != text || old.uri != doc.uri.toString()) {
			host.set(mp, doc.uri.toString(), text);
			project.invalidate(mp);
		}
	}

	static function analyzeDoc(doc:TextDocument):Diagnosis {
		syncDoc(doc);
		var uri = doc.uri.toString();
		var mp = modulePath(doc);
		var d:Null<Diagnosis> = mp != null ? project.diagnoseModule(mp) : null;
		if (d == null)
			d = project.diagnoseStandalone(uri, doc.getText());
		diagnoses.set(uri, d);
		return d;
	}

	static function refreshOne(doc:TextDocument):Void {
		if (doc.languageId != LANG)
			return;
		var d = analyzeDoc(doc);
		diagnostics.set(doc.uri, [for (p in d.problems) toDiagnostic(doc, p)]);
	}

	static function refreshAll():Void
		for (d in Vscode.workspace.textDocuments)
			refreshOne(d);

	static function toDiagnostic(doc:TextDocument, p:Problem):Diagnostic {
		var sev = switch p.severity {
			case SevError: DiagnosticSeverity.Error;
			case SevWarning: DiagnosticSeverity.Warning;
			case SevHint: DiagnosticSeverity.Hint;
		}
		var d = new Diagnostic(range(doc, p.pos), p.message, sev);
		d.source = LANG;
		d.code = p.code;
		if (p.unused)
			d.tags = [DiagnosticTag.Unnecessary];
		return d;
	}

	static function definitionPatterns():Array<String>
		return cfg("definitions", ["neohscript.types.json", "neohscript.generated.json"]);

	static function onJsonChanged(uri:Uri):Void {
		var path = uri.fsPath;
		for (p in definitionPatterns()) {
			var name = p.split("/").pop();
			if (StringTools.endsWith(path, name)) {
				loadDefinitions();
				return;
			}
		}
	}

	static function onSourceChanged(uri:Uri):Void
		Vscode.workspace.openTextDocument(uri).then(function(d:TextDocument) {
			var mp = modulePath(d);
			if (mp != null) {
				host.set(mp, uri.toString(), d.getText());
				project.invalidate(mp);
			}
			refreshAll();
			return null;
		});

	static function indexWorkspace():Void
		Vscode.workspace.findFiles("**/*.hxs", "**/node_modules/**").then(function(uris:Array<Uri>) {
			var remaining = uris.length;
			if (remaining == 0)
				return null;
			for (u in uris) {
				Vscode.workspace.openTextDocument(u).then(function(d:TextDocument) {
					var mp = modulePath(d);
					if (mp != null)
						host.set(mp, u.toString(), d.getText());
					if (--remaining == 0) {
						project.invalidateAll();
						refreshAll();
					}
					return null;
				});
			}
			return null;
		});

	static function loadDefinitions():Void {
		var patterns = definitionPatterns();
		var glob = patterns.length == 1 ? patterns[0] : "{" + patterns.join(",") + "}";
		definitionDiagnostics.clear();
		Vscode.workspace.findFiles(glob, "**/node_modules/**").then(function(uris:Array<Uri>) {
			var texts:Array<{uri:Uri, text:String}> = [];
			var remaining = uris.length;
			if (remaining == 0) {
				applyDefinitions(texts);
				return null;
			}
			for (u in uris) {
				Vscode.workspace.openTextDocument(u).then(function(d:TextDocument) {
					texts.push({uri: u, text: d.getText()});
					if (--remaining == 0)
						applyDefinitions(texts);
					return null;
				});
			}
			return null;
		});
	}

	static function applyDefinitions(texts:Array<{uri:Uri, text:String}>):Void {
		var next = new TypeEnv();
		for (t in texts)
			next.add(t.text, t.uri.toString());
		next.finalize();
		var perFile = new Map<String, Array<Diagnostic>>();
		for (e in next.errors) {
			var list = perFile.get(e.source);
			if (list == null) {
				list = [];
				perFile.set(e.source, list);
			}
			var d = new Diagnostic(new Range(new Position(0, 0), new Position(0, 1)), e.message, DiagnosticSeverity.Warning);
			d.source = LANG;
			list.push(d);
		}
		for (t in texts) {
			var list = perFile.get(t.uri.toString());
			if (list != null)
				definitionDiagnostics.set(t.uri, list);
		}
		project.env = next;
		project.invalidateAll();
		refreshAll();
	}

	static function diagnosisOf(doc:TextDocument):Null<Diagnosis>
		return diagnoses.get(doc.uri.toString());

	static function analyzerOf(doc:TextDocument):Null<Analyzer> {
		var d = diagnosisOf(doc);
		return d == null ? null : d.analyzer;
	}

	static function provideHover(doc:TextDocument, pos:Position, _):Null<Hover> {
		var an = analyzerOf(doc);
		if (an == null)
			return null;
		var h = an.hoverAt(doc.offsetAt(pos));
		return h == null ? null : new Hover(markdown(h.code, h.doc), range(doc, h.pos));
	}

	static function locationOf(loc:neohscript.Ty.SrcLoc, current:TextDocument):Dynamic {
		var uri = toUri(loc.file);
		var text = uri.toString() == current.uri.toString() ? current.getText() : textOfUri(uri.toString());
		if (text != null)
			return new Location(uri, rangeIn(text, {min: loc.min, max: loc.max}));
		return Vscode.workspace.openTextDocument(uri).then(function(d:TextDocument) {
			return new Location(uri, new Range(d.positionAt(loc.min), d.positionAt(loc.max)));
		});
	}

	static function provideDefinition(doc:TextDocument, pos:Position, _):Dynamic {
		var an = analyzerOf(doc);
		if (an == null)
			return null;
		var loc = an.definitionAt(doc.offsetAt(pos));
		return loc == null ? null : locationOf(loc, doc);
	}

	static function siteLocation(uri:String, p:neohscript.Pos):Null<Location> {
		var text = textOfUri(uri);
		return text == null ? null : new Location(toUri(uri), rangeIn(text, p));
	}

	static function collectSites(doc:TextDocument, an:Analyzer, off:Int):Array<{uri:String, pos:neohscript.Pos}> {
		var out:Array<{uri:String, pos:neohscript.Pos}> = [];
		var uri = doc.uri.toString();
		var decl = an.symbols.declAt(off);
		var loc = an.definitionAt(off);
		if (decl != null) {
			out.push({uri: uri, pos: decl.name.pos});
			for (p in an.symbols.referencesTo(decl))
				out.push({uri: uri, pos: p});
			var top = an.symbols.ast.pos;
			if (decl.scope.min == top.min && decl.scope.max == top.max || decl.kind == DMember) {
				for (s in project.referencesTo({file: uri, min: decl.name.pos.min, max: decl.name.pos.max})) {
					var dup = false;
					for (o in out)
						if (o.uri == s.uri && o.pos.min == s.pos.min)
							dup = true;
					if (!dup)
						out.push(s);
				}
			}
		} else if (loc != null) {
			for (s in project.referencesTo(loc))
				out.push(s);
			var own = toUri(loc.file).toString();
			var defText = textOfUri(own);
			if (defText != null)
				out.push({uri: own, pos: {min: loc.min, max: loc.max}});
		}
		return out;
	}

	static function provideReferences(doc:TextDocument, pos:Position, ctx:ReferenceContext, _):Array<Location> {
		var an = analyzerOf(doc);
		if (an == null)
			return [];
		var decl = an.symbols.declAt(doc.offsetAt(pos));
		var sites = collectSites(doc, an, doc.offsetAt(pos));
		var out:Array<Location> = [];
		for (s in sites) {
			if (!ctx.includeDeclaration && decl != null && s.uri == doc.uri.toString() && s.pos.min == decl.name.pos.min)
				continue;
			var l = siteLocation(s.uri, s.pos);
			if (l != null)
				out.push(l);
		}
		return out;
	}

	static function prepareRename(doc:TextDocument, pos:Position, _):Dynamic {
		var an = analyzerOf(doc);
		if (an == null)
			throw new js.lib.Error("Nothing to rename here");
		var off = doc.offsetAt(pos);
		var decl = an.symbols.declAt(off);
		if (decl != null) {
			var r = an.symbols.refAt(off);
			return range(doc, r != null ? r.pos : decl.name.pos);
		}
		var loc = an.definitionAt(off);
		if (loc != null && textOfUri(toUri(loc.file).toString()) != null) {
			var h = an.hoverAt(off);
			if (h != null)
				return range(doc, h.pos);
		}
		throw new js.lib.Error("This symbol is defined by the host and cannot be renamed");
	}

	static function provideRename(doc:TextDocument, pos:Position, newName:String, _):Dynamic {
		var an = analyzerOf(doc);
		if (an == null)
			return null;
		if (!IDENT.match(newName))
			throw new js.lib.Error("\"" + newName + "\" is not a valid identifier");
		var sites = collectSites(doc, an, doc.offsetAt(pos));
		if (sites.length == 0)
			throw new js.lib.Error("This symbol cannot be renamed");
		var edit = new WorkspaceEdit();
		var seen = new Map<String, Bool>();
		for (s in sites) {
			var key = s.uri + ":" + s.pos.min;
			if (seen.exists(key))
				continue;
			seen.set(key, true);
			var text = textOfUri(s.uri);
			if (text == null)
				continue;
			edit.replace(toUri(s.uri), rangeIn(text, s.pos), newName);
		}
		return edit;
	}

	static function provideHighlights(doc:TextDocument, pos:Position, _):Array<DocumentHighlight> {
		var an = analyzerOf(doc);
		if (an == null)
			return [];
		var off = doc.offsetAt(pos);
		var out:Array<DocumentHighlight> = [];
		var decl = an.symbols.declAt(off);
		if (decl != null) {
			out.push(new DocumentHighlight(range(doc, decl.name.pos), DocumentHighlightKind.Write));
			for (p in an.symbols.referencesTo(decl))
				out.push(new DocumentHighlight(range(doc, p), DocumentHighlightKind.Read));
			if (decl.kind == DMember)
				for (p in an.refsToLoc({file: an.uri, min: decl.name.pos.min, max: decl.name.pos.max}))
					out.push(new DocumentHighlight(range(doc, p), DocumentHighlightKind.Read));
			return out;
		}
		var loc = an.definitionAt(off);
		if (loc != null) {
			for (p in an.refsToLoc(loc))
				out.push(new DocumentHighlight(range(doc, p), DocumentHighlightKind.Read));
		}
		return out;
	}

	static function symbolKindOf(d:Decl):Null<SymbolKind>
		return switch d.kind {
			case DFunction: SymbolKind.Function;
			case DFinal: SymbolKind.Constant;
			case DVar: SymbolKind.Variable;
			case DClass: d.tag == "interface" ? SymbolKind.Interface : SymbolKind.Class;
			case DEnum: SymbolKind.Enum;
			case DTypedef: SymbolKind.Struct;
			case DMember:
				if (d.tag == "ctor") SymbolKind.Constructor; else if (d.tag == "method" || d.tag == "static-method") SymbolKind.Method; else SymbolKind.Field;
			default: null;
		}

	static function provideSymbols(doc:TextDocument, _):Array<DocumentSymbol> {
		var d = diagnosisOf(doc);
		if (d == null || d.symbols == null)
			return [];
		var s = d.symbols;
		var an = d.analyzer;
		var top = s.ast.pos;
		var out:Array<DocumentSymbol> = [];
		for (decl in s.decls) {
			if (decl.scope.min != top.min || decl.scope.max != top.max)
				continue;
			var kind = symbolKindOf(decl);
			if (kind == null)
				continue;
			var sym = new DocumentSymbol(decl.name.name, an != null ? an.detailOf(decl) : decl.detail, kind, range(doc, decl.full), range(doc, decl.name.pos));
			if (decl.kind == DClass) {
				for (m in s.decls) {
					if (m.kind != DMember || m.scope.min != decl.full.min || m.scope.max != decl.full.max)
						continue;
					var mk = symbolKindOf(m);
					if (mk != null)
						sym.children.push(new DocumentSymbol(m.name.name, an != null ? an.detailOf(m) : m.detail, mk, range(doc, m.full),
							range(doc, m.name.pos)));
				}
			}
			out.push(sym);
		}
		return out;
	}

	static function exportKind(kind:String):SymbolKind
		return switch kind {
			case "function": SymbolKind.Function;
			case "class": SymbolKind.Class;
			case "interface": SymbolKind.Interface;
			case "enum": SymbolKind.Enum;
			case "typedef": SymbolKind.Struct;
			case "final": SymbolKind.Constant;
			default: SymbolKind.Variable;
		}

	static function provideWorkspaceSymbols(query:String, _):Array<SymbolInformation> {
		var out:Array<SymbolInformation> = [];
		var q = query.toLowerCase();
		for (m in project.allExports()) {
			for (ex in m.exports) {
				if (q != "" && ex.name.toLowerCase().indexOf(q) < 0)
					continue;
				if (ex.loc == null)
					continue;
				var text = textOfUri(m.uri);
				if (text == null)
					continue;
				out.push(new SymbolInformation(ex.name, exportKind(ex.kind), m.module,
					new Location(toUri(m.uri), rangeIn(text, {min: ex.loc.min, max: ex.loc.max}))));
			}
		}
		return out;
	}

	static function provideFolding(doc:TextDocument, _, _):Array<FoldingRange> {
		var d = diagnosisOf(doc);
		if (d == null)
			return [];
		var out:Array<FoldingRange> = [];
		var seen = new Map<Int, Bool>();
		function add(p:neohscript.Pos, kind:Null<FoldingRangeKind>):Void {
			var a = doc.positionAt(p.min).line;
			var b = doc.positionAt(p.max).line;
			var last = doc.getText().charAt(p.max - 1);
			if ((last == "}" || last == "]" || last == ")") && kind == null)
				b--;
			if (b <= a || seen.exists(a))
				return;
			seen.set(a, true);
			out.push(new FoldingRange(a, b, kind));
		}
		var firstImport = -1;
		var lastImport = -1;
		AstTools.iter(d.ast, function(e) {
			switch e.e {
				case EBlock(_), EClass(_), ESwitch(_, _, _), EObject(_), EArrayDecl(_):
					if (e != d.ast)
						add(e.pos, null);
				case EImport(_, _, _), EUsing(_):
					var l = doc.positionAt(e.pos.min).line;
					if (firstImport < 0)
						firstImport = l;
					lastImport = l;
				default:
			}
		});
		for (c in d.comments)
			if (!c.isLine)
				add(c.pos, FoldingRangeKind.Comment);
		if (firstImport >= 0 && lastImport > firstImport)
			out.push(new FoldingRange(firstImport, lastImport, FoldingRangeKind.Imports));
		return out;
	}

	static function provideInlayHints(doc:TextDocument, r:Range, _):Array<InlayHint> {
		var an = analyzerOf(doc);
		if (an == null)
			return [];
		var showTypes:Bool = cfg("inlayHints.types", true);
		var showParams:Bool = cfg("inlayHints.parameters", true);
		var out:Array<InlayHint> = [];
		var seen = new Map<String, Bool>();
		for (h in an.hints) {
			if (h.kind == "type" && !showTypes)
				continue;
			if (h.kind == "param" && !showParams)
				continue;
			var p = doc.positionAt(h.pos);
			if (!r.contains(p))
				continue;
			var key = h.pos + h.label;
			if (seen.exists(key))
				continue;
			seen.set(key, true);
			var hint = new InlayHint(p, h.label, h.kind == "type" ? InlayHintKind.Type : InlayHintKind.Parameter);
			if (h.kind == "param")
				hint.paddingRight = true;
			out.push(hint);
		}
		return out;
	}

	static function provideSemanticTokens(doc:TextDocument, _):Dynamic {
		var builder = new SemanticTokensBuilder(new SemanticTokensLegend(TOKEN_TYPES, TOKEN_MODS));
		var an = analyzerOf(doc);
		if (an == null)
			return builder.build();
		for (t in an.semanticTokens()) {
			var ti = TOKEN_TYPES.indexOf(t.type);
			if (ti < 0 || t.pos.max <= t.pos.min)
				continue;
			var mods = 0;
			for (m in t.mods) {
				var mi = TOKEN_MODS.indexOf(m);
				if (mi >= 0)
					mods |= 1 << mi;
			}
			var p = doc.positionAt(t.pos.min);
			var e = doc.positionAt(t.pos.max);
			if (p.line != e.line)
				continue;
			builder.push(p.line, p.character, e.character - p.character, ti, mods);
		}
		return builder.build();
	}

	static function provideFormatting(doc:TextDocument, options:FormattingOptions, _):Array<TextEdit> {
		var text = doc.getText();
		var formatted = Formatter.format(text, Std.int(options.tabSize), !options.insertSpaces);
		if (formatted == text)
			return [];
		return [
			TextEdit.replace(new Range(doc.positionAt(0), doc.positionAt(text.length)), formatted)
		];
	}

	static function memberItem(m:Member):CompletionItem {
		var isFn = switch TyTools.unwrap(m.t) {
			case TyFun(_, _), TyForall(_, _): true;
			default: false;
		}
		var it = new CompletionItem(m.name, isFn ? CompletionItemKind.Method : CompletionItemKind.Field);
		it.detail = TyTools.memberCode(m);
		if (m.doc != null)
			it.documentation = markdown(null, m.doc);
		return it;
	}

	static function typeItems():Array<CompletionItem> {
		var out:Array<CompletionItem> = [];
		for (t in BASIC_TYPES)
			out.push(new CompletionItem(t, CompletionItemKind.Class));
		for (t in project.env.typeNames()) {
			var kind = switch t.kind {
				case "enum": CompletionItemKind.Enum;
				case "typedef": CompletionItemKind.Interface;
				case "interface": CompletionItemKind.Interface;
				default: CompletionItemKind.Class;
			}
			var it = new CompletionItem(t.name, kind);
			it.detail = t.kind + " " + (t.pack != "" ? t.pack + "." : "") + t.name;
			if (t.doc != null)
				it.documentation = markdown(null, t.doc);
			out.push(it);
		}
		return out;
	}

	static function importItems(path:String):Array<CompletionItem> {
		var out:Array<CompletionItem> = [];
		var parts = path.split(".");
		parts.pop();
		var base = parts.join(".");
		var seen = new Map<String, Bool>();
		function add(name:String, kind:CompletionItemKind, detail:String):Void {
			if (seen.exists(name))
				return;
			seen.set(name, true);
			var it = new CompletionItem(name, kind);
			it.detail = detail;
			out.push(it);
		}
		for (p in host.subPackages(base))
			add(p, CompletionItemKind.Folder, "package");
		for (m in host.modulesIn(base))
			add(m, CompletionItemKind.Module, "module " + (base == "" ? m : base + "." + m));
		if (host.exists(base)) {
			for (ex in project.exportsOf(base))
				add(ex.name, exportItemKind(ex.kind), ex.kind + " " + ex.name);
		}
		for (t in project.env.typeNames()) {
			if (t.pack == base)
				add(t.name, CompletionItemKind.Class, t.kind + " " + t.name);
			else if (base == "" && t.pack != "")
				add(t.pack.split(".")[0], CompletionItemKind.Folder, "package");
			else if (StringTools.startsWith(t.pack, base + "."))
				add(t.pack.substr(base.length + 1).split(".")[0], CompletionItemKind.Folder, "package");
		}
		return out;
	}

	static function exportItemKind(kind:String):CompletionItemKind
		return switch kind {
			case "function": CompletionItemKind.Function;
			case "class": CompletionItemKind.Class;
			case "interface": CompletionItemKind.Interface;
			case "enum": CompletionItemKind.Enum;
			case "typedef": CompletionItemKind.Interface;
			case "final": CompletionItemKind.Constant;
			default: CompletionItemKind.Variable;
		}

	static function importEdit(doc:TextDocument, d:Diagnosis, path:String):TextEdit {
		var after = -1;
		AstTools.iter(d.ast, function(e) {
			switch e.e {
				case EImport(_, _, _), EUsing(_):
					after = Std.int(Math.max(after, e.pos.max));
				default:
			}
		});
		if (after < 0)
			return TextEdit.insert(new Position(0, 0), "import " + path + ";\n");
		var line = doc.positionAt(after).line;
		return TextEdit.insert(new Position(line + 1, 0), "import " + path + ";\n");
	}

	static function provideCompletion(doc:TextDocument, pos:Position, _, _):Array<CompletionItem> {
		var prefix = doc.lineAt(pos.line).text.substr(0, pos.character);
		var an = analyzerOf(doc);
		var d = diagnosisOf(doc);
		var off = doc.offsetAt(pos);

		if (IMPORT_CTX.match(prefix))
			return importItems(IMPORT_CTX.matched(2));
		if (TYPE_ANNOT.match(prefix) || NEW_CTX.match(prefix))
			return typeItems();

		if (ACCESS_CHAIN.match(prefix)) {
			if (an == null)
				return [];
			var chain = StringTools.replace(StringTools.replace(ACCESS_CHAIN.matched(1), "?", ""), " ", "").split(".");
			var accessOff = off;
			var t = StringTools.rtrim(prefix);
			if (StringTools.endsWith(t, ".")) {
				accessOff = off - 1;
				if (t.length >= 2 && t.charAt(t.length - 2) == "?")
					accessOff = off - 2;
			}
			return [for (m in an.membersAt(chain, accessOff)) memberItem(m)];
		}

		if (MEMBER_ACCESS.match(prefix)) {
			if (an == null)
				return [];
			var mpos = MEMBER_ACCESS.matchedPos();
			var beforeDot = prefix.substring(0, mpos.pos + mpos.len - 1);
			var chainRegex = ~/([A-Za-z_]\w*(?:\s*\??\.\s*[A-Za-z_]\w*)*)\s*\??\.\s*$/;
			if (!chainRegex.match(beforeDot + "."))
				return [];
			var chain = StringTools.replace(StringTools.replace(chainRegex.matched(1), "?", ""), " ", "").split(".");
			return [for (m in an.membersAt(chain, off)) memberItem(m)];
		}

		var out:Array<CompletionItem> = [];
		var visible = new Map<String, Bool>();
		var s = d == null ? null : d.symbols;
		if (s != null) {
			for (decl in s.visibleAt(off)) {
				var kind = switch decl.kind {
					case DFunction: CompletionItemKind.Function;
					case DFinal: CompletionItemKind.Constant;
					case DClass: CompletionItemKind.Class;
					case DEnum: CompletionItemKind.Enum;
					case DTypedef: CompletionItemKind.Interface;
					case DMember: decl.tag == "method" || decl.tag == "static-method" ? CompletionItemKind.Method : CompletionItemKind.Field;
					default: CompletionItemKind.Variable;
				}
				var it = new CompletionItem(decl.name.name, kind);
				it.detail = an != null ? an.detailOf(decl) : decl.detail;
				if (decl.doc != null)
					it.documentation = markdown(null, decl.doc);
				it.sortText = "0" + decl.name.name;
				visible.set(decl.name.name, true);
				out.push(it);
			}
		}
		if (an != null) {
			for (ex in an.importedNames()) {
				var it = new CompletionItem(ex.name, exportItemKind(ex.kind));
				it.detail = ex.kind + " " + ex.name + " (" + ex.module + ")";
				if (ex.doc != null)
					it.documentation = markdown(null, ex.doc);
				it.sortText = "0" + ex.name;
				visible.set(ex.name, true);
				out.push(it);
			}
		}
		for (g in project.env.globals) {
			var it = new CompletionItem(g.name, TyTools.unwrap(g.t).match(TyFun(_, _)) ? CompletionItemKind.Function : CompletionItemKind.Variable);
			it.detail = TyTools.memberCode(g);
			if (g.doc != null)
				it.documentation = markdown(null, g.doc);
			it.sortText = "1" + g.name;
			visible.set(g.name, true);
			out.push(it);
		}
		for (t in project.env.typeNames()) {
			if (t.kind == "typedef")
				continue;
			var it = new CompletionItem(t.name, t.kind == "enum" ? CompletionItemKind.Enum : CompletionItemKind.Class);
			it.detail = t.kind + " " + t.name;
			if (t.doc != null)
				it.documentation = markdown(null, t.doc);
			it.sortText = "1" + t.name;
			visible.set(t.name, true);
			out.push(it);
		}
		for (g in cfg("globals", DEFAULT_GLOBALS)) {
			var it = new CompletionItem(g, CompletionItemKind.Module);
			it.detail = "(host global)";
			it.sortText = "2" + g;
			out.push(it);
		}
		if (d != null) {
			var count = 0;
			for (m in project.allExports()) {
				if (m.uri == doc.uri.toString())
					continue;
				for (ex in m.exports) {
					if (visible.exists(ex.name) || count > 200)
						continue;
					count++;
					var it = new CompletionItem(ex.name, exportItemKind(ex.kind));
					it.detail = "auto-import from " + m.module;
					if (ex.doc != null)
						it.documentation = markdown(null, ex.doc);
					it.sortText = "5" + ex.name;
					it.additionalTextEdits = [importEdit(doc, d, m.module + "." + ex.name)];
					out.push(it);
				}
			}
		}
		for (sn in SNIPPETS) {
			var it = new CompletionItem(sn.label, CompletionItemKind.Snippet);
			it.detail = sn.detail;
			it.insertText = new SnippetString(sn.body);
			it.sortText = "3" + sn.label;
			out.push(it);
		}
		for (k in KEYWORDS) {
			var it = new CompletionItem(k, CompletionItemKind.Keyword);
			it.sortText = "4" + k;
			out.push(it);
		}
		return out;
	}

	static function provideSignature(doc:TextDocument, pos:Position, _, _):Null<SignatureHelp> {
		var an = analyzerOf(doc);
		if (an == null)
			return null;
		var off = doc.offsetAt(pos);
		var full = doc.getText();
		var text = full.substring(Std.int(Math.max(0, off - 2000)), off);

		var depth = 0;
		var commas = 0;
		var open = -1;
		var i = text.length - 1;
		while (i >= 0) {
			var c = text.charAt(i);
			if (c == ")" || c == "]" || c == "}")
				depth++;
			else if (c == "(" || c == "[" || c == "{") {
				if (depth == 0) {
					if (c != "(")
						return null;
					open = i;
					break;
				}
				depth--;
			} else if (c == "," && depth == 0)
				commas++;
			i--;
		}
		if (open < 0)
			return null;

		var before = text.substr(0, open);
		if (!CALLEE.match(before))
			return null;
		var calleeStart = CALLEE.matchedPos().pos;
		var chain = StringTools.replace(StringTools.replace(CALLEE.matched(1), "?", ""), " ", "").split(".");
		var isNew = NEW_BEFORE.match(before.substr(0, calleeStart));

		var callable = isNew ? an.constructorOf(chain.join(".")) : an.callableAt(chain, off);
		if (callable == null)
			return null;

		var label = TyTools.signature(callable.name, callable.args, callable.ret, callable.tparams);
		var info = new SignatureInformation(label, markdown(null, callable.doc, false));
		var params:Array<ParameterInformation> = [];
		for (a in callable.args) {
			var pdoc:Null<String> = a.doc;
			if (pdoc == null && callable.doc != null) {
				var p = DocTools.paramDoc(callable.doc, a.name);
				if (p != null && p.text != "")
					pdoc = p.text;
			}
			params.push(new ParameterInformation((a.opt ? "?" : "") + a.name + ":" + TyTools.str(a.t), pdoc));
		}
		info.parameters = params;
		var help = new SignatureHelp();
		help.signatures = [info];
		help.activeSignature = 0;
		help.activeParameter = Std.int(Math.min(commas, Math.max(0, callable.args.length - 1)));
		return help;
	}

	static function deleteStatement(doc:TextDocument, p:neohscript.Pos):Range {
		var text = doc.getText();
		var end = p.max;
		while (end < text.length && (text.charAt(end) == " " || text.charAt(end) == "\t"))
			end++;
		if (end < text.length && text.charAt(end) == ";")
			end++;
		var lineStart = p.min;
		while (lineStart > 0 && (text.charAt(lineStart - 1) == " " || text.charAt(lineStart - 1) == "\t"))
			lineStart--;
		var onlyBefore = lineStart == 0 || text.charAt(lineStart - 1) == "\n";
		var tail = end;
		while (tail < text.length && (text.charAt(tail) == " " || text.charAt(tail) == "\t"))
			tail++;
		if (onlyBefore && (tail >= text.length || text.charAt(tail) == "\n" || text.charAt(tail) == "\r")) {
			if (tail < text.length && text.charAt(tail) == "\r")
				tail++;
			if (tail < text.length && text.charAt(tail) == "\n")
				tail++;
			return new Range(doc.positionAt(lineStart), doc.positionAt(tail));
		}
		return new Range(doc.positionAt(p.min), doc.positionAt(end));
	}

	static function quickFix(title:String, doc:TextDocument, diag:Diagnostic, edit:WorkspaceEdit, preferred:Bool = false):CodeAction {
		var a = new CodeAction(title, CodeActionKind.QuickFix);
		a.edit = edit;
		a.diagnostics = [diag];
		a.isPreferred = preferred;
		return a;
	}

	static function provideCodeActions(doc:TextDocument, r:Range, ctx:CodeActionContext, _):Array<CodeAction> {
		var d = diagnosisOf(doc);
		var an = analyzerOf(doc);
		var out:Array<CodeAction> = [];
		if (d == null)
			return out;
		for (diag in ctx.diagnostics) {
			var code = Std.string(diag.code);
			var start = doc.offsetAt(diag.range.start);
			var end = doc.offsetAt(diag.range.end);
			switch code {
				case "unused":
					if (an != null) {
						var decl = an.symbols.declAt(start);
						if (decl != null) {
							var e = new WorkspaceEdit();
							e.delete(doc.uri, deleteStatement(doc, decl.full));
							out.push(quickFix('Remove unused "' + decl.name.name + '"', doc, diag, e, true));
						}
					}
				case "unused-import":
					var e = new WorkspaceEdit();
					e.delete(doc.uri, deleteStatement(doc, {min: start, max: end}));
					out.push(quickFix("Remove unused import", doc, diag, e, true));
				case "unused-param":
					var e = new WorkspaceEdit();
					e.insert(doc.uri, diag.range.start, "_");
					out.push(quickFix("Prefix parameter with an underscore", doc, diag, e));
				case "undefined-variable", "unknown-type":
					var name = doc.getText(diag.range);
					var seen = new Map<String, Bool>();
					for (m in project.allExports()) {
						if (m.uri == doc.uri.toString())
							continue;
						for (ex in m.exports) {
							if (ex.name != name)
								continue;
							var path = m.module + "." + name;
							if (seen.exists(path))
								continue;
							seen.set(path, true);
							var e = new WorkspaceEdit();
							e.insert(doc.uri, importEdit(doc, d, path).range.start, importEdit(doc, d, path).newText);
							out.push(quickFix("Import " + path, doc, diag, e, true));
						}
					}
					for (t in project.env.typeNames()) {
						if (t.name != name || t.pack == "")
							continue;
						var path = t.pack + "." + name;
						if (seen.exists(path))
							continue;
						seen.set(path, true);
						var e = new WorkspaceEdit();
						e.insert(doc.uri, importEdit(doc, d, path).range.start, importEdit(doc, d, path).newText);
						out.push(quickFix("Import " + path, doc, diag, e, true));
					}
				case "non-exhaustive":
					var marker = "missing: ";
					var at = diag.message.indexOf(marker);
					if (at >= 0) {
						var names = diag.message.substr(at + marker.length).split(", ");
						var node = AstTools.findAt(d.ast, start);
						var found:Null<Expr> = null;
						AstTools.iter(d.ast, function(x) {
							switch x.e {
								case ESwitch(sx, _, _):
									if (sx.pos.min == start)
										found = x;
								default:
							}
						});
						if (found != null) {
							var insertAt = found.pos.max - 1;
							var e = new WorkspaceEdit();
							var text = [for (n in names) "\tcase " + n + ":\n\t\t\n"].join("");
							e.insert(doc.uri, doc.positionAt(insertAt), text);
							out.push(quickFix("Add missing cases", doc, diag, e, true));
						}
						if (node == null)
							continue;
					}
				case "missing-override":
					var e = new WorkspaceEdit();
					var memberStart = start;
					AstTools.iter(d.ast, function(x) {
						switch x.e {
							case EClass(c):
								for (m in c.members)
									if (m.name.pos.min == start)
										memberStart = m.pos.min;
							default:
						}
					});
					e.insert(doc.uri, doc.positionAt(memberStart), "override ");
					out.push(quickFix('Add "override"', doc, diag, e, true));
				default:
			}
		}
		if (an != null) {
			var off = doc.offsetAt(r.start);
			AstTools.iter(d.ast, function(x) {
				switch x.e {
					case EVar(n, null, init, _):
						if (init != null && off >= n.pos.min && off <= n.pos.max) {
							var t = an.declTypes.get(n.pos.min);
							if (t != null) {
								var s = TyTools.str(TyTools.zonk(t));
								if (s != "Dynamic" && s != "Null") {
									var a = new CodeAction("Add type annotation :" + s, CodeActionKind.RefactorRewrite);
									var e = new WorkspaceEdit();
									e.insert(doc.uri, doc.positionAt(n.pos.max), ":" + s);
									a.edit = e;
									out.push(a);
								}
							}
						}
					default:
				}
			});
		}
		return out;
	}

	static function generateDocs():Dynamic {
		var md = DocGen.markdown(project.env, project.allExports());
		return Vscode.workspace.openTextDocument({content: md, language: "markdown"}).then(function(d:TextDocument) {
			return Vscode.window.showTextDocument(d);
		});
	}
}
