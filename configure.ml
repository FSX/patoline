let prefix=ref "/usr/"
let bin_dir=ref ""
let fonts_dir=ref ""
let grammars_dir=ref ""
let hyphen_dir=ref ""
let ocaml_lib_dir=ref ""
let ocamlfind_dir=ref ""
let fonts_dirs=ref []
let grammars_dirs=ref []
let hyphen_dirs=ref []
let opt_only=ref false

open Arg
let rec escape s=
  try
    let i=String.index s ' ' in
      String.sub s 0 i ^ "\\ " ^ (escape (String.sub s (i+1) (String.length s-i-1)))
  with
      Not_found -> s


let _=
  parse [
    ("--prefix", Set_string prefix, "  prefix (/usr/local/ by default)");
    ("--bin-prefix", Set_string bin_dir, "  directory for the binaries ($PREFIX/bin/ by default)");
    ("--ocaml-libs", Set_string ocaml_lib_dir, "  directory for the caml libraries ($PREFIX/lib/ocaml/ by default; `ocamlc -where` is another sensible choice)");
    ("--ocamlfind-dir", Set_string ocamlfind_dir, "  directory for the caml libraries ($PREFIX/lib/ocaml/ by default; `ocamlc -where` is another sensible choice)");
    ("--fonts-dir", Set_string fonts_dir, "  directory for the fonts ($PREFIX/share/texprime/fonts/ by default)");
    ("--grammars-dir", Set_string grammars_dir, "  directory for the grammars ($PREFIX/share/texprime/grammars/ by default)");
    ("--hyphen-dir", Set_string hyphen_dir, "  directory for the hyphenation dictionnaries ($PREFIX/share/texprime/hyphen/ by default)");
    ("--extra-fonts-dir", String (fun pref->fonts_dirs:=pref:: !fonts_dirs), "  additional directories texprime should scan for fonts");
    ("--extra-grammars-dir", String (fun pref->grammars_dirs:=pref:: !grammars_dirs), "  additional directories texprime should scan for grammars");
    ("--extra-hyphen-dir", String (fun pref->hyphen_dirs:=pref:: !hyphen_dirs), "  additional directories texprime should scan for hyphenation dictionaries");
    ("--opt-only", Unit (fun ()->opt_only:=true), "  native version only (both native and bytecode are compiled by default)")
  ] ignore "Usage:";
  if !bin_dir="" then bin_dir:=Filename.concat !prefix "bin/";
  if !ocaml_lib_dir="" then ocaml_lib_dir:=Filename.concat !prefix "lib/ocaml";

  if !fonts_dir="" then fonts_dir:=Filename.concat !prefix "share/texprime/fonts";
  if !grammars_dir="" then grammars_dir:=Filename.concat !prefix "share/texprime/grammars";
  if !hyphen_dir="" then hyphen_dir:=Filename.concat !prefix "share/texprime/hyphen";

  fonts_dirs:= !fonts_dir ::(List.rev !fonts_dirs);
  grammars_dirs:= !grammars_dir ::(List.rev !grammars_dirs);
  hyphen_dirs:= !hyphen_dir ::(List.rev !hyphen_dirs);

  let out=open_out "Makefile" in
  let config=open_out "src/Typography/Config.ml" in

  let fonts_src_dir="Otf" in
  let grammars_src_dir="src" in
  let hyphen_src_dir="Hyphenation" in

    Printf.fprintf out "all:\n\tmake -C src %s\n" (if !opt_only then "opt" else "all");

    Printf.fprintf out "install:\n";
    Printf.fprintf out "\t#fonts\n";
    let rec read_fonts dir =
      Printf.fprintf out "\tinstall -m 755 -d $(DESTDIR)/%s\n" (escape (Filename.concat !fonts_dir dir));
      List.iter (fun f->
        let f = Filename.concat dir f in
        if Sys.is_directory f
        then read_fonts f
        else if Filename.check_suffix f ".otf" then
          Printf.fprintf out "\tinstall -m 644 %s $(DESTDIR)/%s\n"
            (escape (Filename.concat fonts_src_dir f))
            (escape (Filename.concat !fonts_dir f))
            ) (Array.to_list (Sys.readdir dir))
    in
    let cdir = Sys.getcwd () in
      Sys.chdir fonts_src_dir;
      read_fonts "./";
      Sys.chdir cdir;

    (* Grammars *)
    Printf.fprintf out "\t#grammars\n";
    Printf.fprintf out "\tinstall -m 755 -d $(DESTDIR)/%s\n" (escape !grammars_dir);
    List.iter (fun x->
                 if Filename.check_suffix x ".tgo" || Filename.check_suffix x ".tgx" then
                   Printf.fprintf out "\tinstall -m 644 %s $(DESTDIR)/%s\n" (escape (Filename.concat grammars_src_dir x)) (escape (List.hd !grammars_dirs))
              ) ("texprimeDefault.tgx"::(if !opt_only then [] else ["texprimeDefault.tgo"])@Array.to_list (Sys.readdir grammars_src_dir));

    (* Hyphenation *)
    Printf.fprintf out "\t#hyphenation\n";
    Printf.fprintf out "\tinstall -m 755 -d $(DESTDIR)/%s\n" (escape !hyphen_dir);
    List.iter (fun x->
                 if Filename.check_suffix x ".hdict" then
                   Printf.fprintf out "\tinstall -m 644 %s $(DESTDIR)/%s\n" (escape (Filename.concat hyphen_src_dir x)) (escape !hyphen_dir)
              ) (Array.to_list (Sys.readdir hyphen_src_dir));
    (* binaries *)
    Printf.fprintf out "\t#binaries\n";
    Printf.fprintf out "\tinstall -m 755 src/texprime $(DESTDIR)/%s\n" (escape !bin_dir);
    let sources=
      "src/Typography/Typography.cmxa src/Typography/Typography.a src/Typography/Typography.cmi "^
        "src/DefaultFormat.cmxa src/DefaultFormat.a src/DefaultFormat.cmi "^
        (if not !opt_only then "src/Typography/Typography.cma  src/DefaultFormat.cma " else "")
    in
      Printf.fprintf out "\tinstall -m 755 -d $(DESTDIR)/%s/Typography\n" (escape !ocaml_lib_dir);
      Printf.fprintf out "\tinstall -m 644 %s $(DESTDIR)/%s/Typography\n" sources (escape !ocaml_lib_dir);

      Printf.fprintf out "\tinstall -m 755 -d $(DESTDIR)/%s/Typography\n" (escape !ocaml_lib_dir);


      (* Installation pour ocamlfind (casse la chaine de compilation de Guillaume sans ça) *)
      (*Printf.fprintf out "\tinstall -m 755 -d $(DESTDIR)/%s/stublibs\n" * (escape !ocaml_lib_dir);*)
      Printf.fprintf out "\tinstall -m 755 -d $(DESTDIR)%s/Typography\n" (if !ocamlfind_dir="" then "$(shell ocamlfind printconf destdir)" else escape !ocamlfind_dir);
      Printf.fprintf out "\tinstall -m 644 src/Typography/META %s $(DESTDIR)%s/Typography\n" sources (if !ocamlfind_dir="" then "$(shell ocamlfind printconf destdir)" else escape !ocamlfind_dir);

      (* proof *)
      Printf.fprintf out "\tmake -C proof install DESTDIR=$(DESTDIR) PREFIX=%s\n" (escape !bin_dir);


    Printf.fprintf config "let fontsdir=ref [%s]\nlet bindir=ref [\"%s\"]\nlet grammarsdir=ref [%s]\nlet hyphendir=ref [%s]\n"
      (String.concat ";" (List.map (fun s->"\""^s^"\"") (!fonts_dirs)))
      !bin_dir
      (String.concat ";" (List.map (fun s->"\""^s^"\"") (!grammars_dirs)))
      (String.concat ";" (List.map (fun s->"\""^s^"\"") (!hyphen_dirs)));
    Printf.fprintf out "clean:\n\tmake -C src clean\n";
    close_out out;
    close_out config;
