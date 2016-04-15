(*
  Copyright Florian Hatat, Tom Hirschowitz, Pierre Hyvernat,
  Pierre-Etienne Meunier, Christophe Raffalli, Guillaume Theyssier 2012.

  This file is part of Patoline.

  Patoline is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Patoline is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Patoline.  If not, see <http://www.gnu.org/licenses/>.
*)

(* Initialization. *)
let _ = Findlib.init ~env_ocamlpath:"src"
let configure_environment = Unix.environment ()

(* Command-line arguments management and default configuration. *)
let prefix         = ref "/usr/local/"
let bindir         = ref (Filename.concat !prefix "bin/")
let fonts_dir      = ref (Filename.concat !prefix "share/patoline/fonts")
let grammars_dir   = ref (Filename.concat !prefix "lib/patoline/grammars")
let hyphen_dir     = ref (Filename.concat !prefix "share/patoline/hyphen")
let ocaml_lib_dir  = ref (Findlib.default_location ())
let ocaml_dlls_dir = ref (Filename.concat !ocaml_lib_dir "stublibs")
let fonts_dirs     = ref []
let grammars_dirs  = ref []
let plugins_dir    = ref (Filename.concat !prefix "lib/patoline/plugins")
let plugins_dirs   = ref []
let hyphen_dirs    = ref []
let driver_dir     = ref (Filename.concat !ocaml_lib_dir "Typography")
let lang           = ref "EN"
let ban_comic_sans = ref false
let pdf_type3_only = ref false
let driver_blist   = ref []

let add_font_dir     d = fonts_dirs    := d :: !fonts_dirs
let add_grammar_dir  d = grammars_dirs := d :: !grammars_dirs
let add_hyphen_dir   d = hyphen_dirs   := d :: !hyphen_dirs
let blacklist_driver d = driver_blist  := d :: !driver_blist

let languages =
  let f = open_in "src/Typography/TypoLanguage.ml" in
  let buf = Bytes.create (in_channel_length f) in
  really_input f buf 0 (in_channel_length f);
  close_in f;
  let rec make_str i acc =
    if i > String.length buf - 7 then acc
    else if String.sub buf i 5 = "LANG_" then
      make_str (i+7) (String.sub buf (i+5) 2 :: acc)
    else make_str (i+1) acc
  in make_str 0 []

let set_language l =
  let l = String.uppercase l in
  if List.mem l languages then lang := l else
  Printf.eprintf "Unknown language %S... using default.\n" l

let languages_string = String.concat ", " (List.rev languages)

let spec =
  [ ("--prefix", Arg.Set_string prefix,
       Printf.sprintf "Set prefix (default is %S)." !prefix)
  ; ("--bindir", Arg.Set_string bindir,
       Printf.sprintf "Set bindir (default is %S)." !bindir)
  ; ("--ocaml-libs", Arg.Set_string ocaml_lib_dir,
       Printf.sprintf "Set library directory (default is %S)." !ocaml_lib_dir)
  ; ("--ocaml-dlls", Arg.Set_string ocaml_dlls_dir,
       Printf.sprintf "Set stubs directory (default is %S)." !ocaml_dlls_dir)
  ; ("--fonts-dir", Arg.Set_string fonts_dir,
       Printf.sprintf "Set font directory (default is %S)." !fonts_dir)
  ; ("--grammars-dir", Arg.Set_string grammars_dir,
       Printf.sprintf "Set grammar directory (default is %S)." !grammars_dir)
  ; ("--plugins-dir", Arg.Set_string plugins_dir,
       Printf.sprintf "Set plugins directory (default is %S)." !plugins_dir)
  ; ("--driver-dir", Arg.Set_string driver_dir,
       Printf.sprintf "Set driver directory (default is %S)." !driver_dir)
  ; ("--hyphen-dir", Arg.Set_string hyphen_dir,
       Printf.sprintf "Set hypenation dictionaries directory (default is %S)."
       !hyphen_dir)
  ; ("--extra-fonts-dir", Arg.String add_font_dir,
       "Add a dirrectory in which Patoline will look for fonts.")
  ; ("--extra-grammars-dir", Arg.String add_grammar_dir,
       "Add a dirrectory in which Patoline will look for grammars.")
  ; ("--extra-hyphen-dir", Arg.String add_hyphen_dir,
       "Add a dirrectory in which Patoline will look for hyphenation dicts.")
  ; ("--ban-comic-sans", Arg.Set ban_comic_sans,
       "Disallows ComicSans font.")
  ; ("--pdf-type3-only", Arg.Set pdf_type3_only,
       "Convert all fonts to vector graphics in PDFs.")
      (* This option improves compatibility, but may worsen font rasterizing
         in some readers. *)
  ; ("--lang", Arg.String set_language,
       Printf.sprintf "Set the language for error messages (available: %s)."
       languages_string)
  ; ("--without", Arg.String blacklist_driver,
       "Blacklist a driver (will not be compiled / installed).") ]

let _ =
  Arg.parse spec ignore "Usage:"

let _ =
  fonts_dirs    := !fonts_dir    :: !fonts_dirs;
  grammars_dirs := !grammars_dir :: !grammars_dirs;
  hyphen_dirs   := !hyphen_dir   :: !hyphen_dirs;
  plugins_dirs  := !plugins_dir  :: !plugins_dirs

(* Management of local packages. *)
type local_packages =
  { package_name : string
  ; macro_suffix : string
  ; local_deps   : string list
  ; extern_deps  : string list
  ; subdirs      : string list
  ; has_meta     : bool }

let local_packages =
  [ { package_name = "patutil"
    ; macro_suffix = "UTIL"
    ; local_deps   = ["rbuffer"; "unicodelib"]
    ; extern_deps  = ["bytes"]
    ; subdirs      = []
    ; has_meta     = true }

  ; { package_name = "rawlib"
    ; macro_suffix = "RAWLIB"
    ; local_deps   = ["patutil"; "patfonts"]
    ; extern_deps  = ["dynlink"; "imagelib"]
    ; subdirs      = []
    ; has_meta     = true }

  ; { package_name = "unicodelib"
    ; macro_suffix = "UNICODELIB"
    ; local_deps   = []
    ; extern_deps  = ["bytes"; "decap"; "sqlite3"; "compiler-libs" ]
    ; subdirs      = []
    ; has_meta     = true }

  ; { package_name = "rbuffer"
    ; macro_suffix = "RBUFFER"
    ; local_deps   = []
    ; extern_deps  = []
    ; subdirs      = []
    ; has_meta     = true }

  ; { package_name = "patfonts"
    ; macro_suffix = "FONTS"
    ; local_deps   = ["patutil"; "unicodelib"]
    ; extern_deps  = []
    ; subdirs      = ["CFF";"Opentype";"unicodeRanges"]
    ; has_meta     = true }

  ; { package_name = "bibi"
    ; macro_suffix = "BIBI"
    ; local_deps   = ["Typography"; "patutil"; "unicodelib"]
    ; extern_deps  = ["sqlite3"]
    ; subdirs      = []
    ; has_meta     = true }

  ; { package_name = "db"
    ; macro_suffix = "DB"
    ; local_deps   = ["patutil"]
    ; extern_deps  = ["mysql"]
    ; subdirs      = []
    ; has_meta     = true }

  ; { package_name = "Typography"
    ; macro_suffix = "TYPOGRAPHY"
    ; local_deps = ["patutil";"patfonts";"unicodelib";"cesure";"rawlib";"db"]
    ; extern_deps  = ["zip"; "fontconfig"; "imagelib"; "bytes"]
    ; subdirs      = ["DefaultFormat"]
    ; has_meta     = true }

  ; { package_name = "plot"
    ; macro_suffix = "PLOT"
    ; local_deps   = ["Typography"; "rawlib"]
    ; extern_deps  = []
    ; subdirs      = []
    ; has_meta     = true }

  (* FAKE: no META yet *)
  ; { package_name = "Format"
    ; macro_suffix = "FORMAT"
    ; local_deps   = ["Typography";"cesure";"rawlib";"db"]
    ; extern_deps  = ["bytes"]
    ; subdirs      = []
    ; has_meta     = false }

  ; { package_name = "patobuild"
    ; macro_suffix = "PATOBUILD"
    ; local_deps   = ["Typography";"plugins"]
    ; extern_deps  = ["decap";"bytes";"compiler-libs"]
    ; subdirs      = []
    ; has_meta     = false }

  ; { package_name = "Drivers"
    ; macro_suffix = "DRIVERS"
    ; local_deps   = ["rawlib";"db"]
    ; extern_deps  = []
    ; subdirs      = []
    ; has_meta     = false }

  ; { package_name = "cesure"
    ; macro_suffix = "CESURE"
    ; local_deps   = ["unicodelib"]
    ; extern_deps  = ["decap"]
    ; subdirs      = []
    ; has_meta     = false }

  ; { package_name = "proof"
    ; macro_suffix = "PROOF"
    ; local_deps   = ["rawlib"] (* Pdf Driver added by hand *)
    ; extern_deps  = []
    ; subdirs      = []
    ; has_meta     = false }

  ; { package_name = "plugins"
    ; macro_suffix = "PLUGINS"
    ; local_deps   = ["Format"]
    ; extern_deps  = ["unix"]
    ; subdirs      = []
    ; has_meta     = false }

  ]

let is_local_package name =
  List.exists (fun p -> name = p.package_name) local_packages

let find_local_package name =
  try List.find (fun p -> name = p.package_name) local_packages
  with Not_found ->
    Printf.printf "Did not find local package \"%s\"...\n%!" name;
    raise Not_found

let packages_local names =
  let add acc d = if List.mem d acc then acc else d::acc in
  let rec fn acc name =
    let p = find_local_package name in
    if p.has_meta then add acc p.package_name
    else List.fold_left fn (List.fold_left add acc p.extern_deps) p.local_deps
  in List.fold_left fn [] names

let includes_local_list ?(subdir_only=true) name =
  let add d acc = if List.mem d acc then acc else d::acc in
  let rec fn acc name =
    let p = find_local_package name in
    let acc =
      if subdir_only && p.has_meta then acc
      else add ("-I "^(Filename.concat "src" p.package_name)) acc
    in
    let acc = List.fold_left (fun acc s ->
      add ("-I "^(Filename.concat "src" (Filename.concat p.package_name s))) acc)
      acc p.subdirs
    in
    List.fold_left fn acc p.local_deps
  in fn [] name

let includes_local ?(subdir_only=true) name =
  String.concat " " (includes_local_list ~subdir_only name)

(* Management of findlib packages. *)
type findlib_package =
  (* Name of the package. *)
  { fl_package_name     : string
  (* We try to guess package name using a list of known aliases. *)
  ; fl_known_aliases    : string list
  (* Additional checks function and the associated error message. *)
  ; fl_additional_check : ((string -> string -> bool) * string) option }

let fl_package name aliases =
  { fl_package_name     = name
  ; fl_known_aliases    = aliases
  ; fl_additional_check = None }

let package_min_version min_version package alias =
  (* parse_version splits a string representing a version number to a
   * tuple which can be compared to other version numbers using OCaml
   * regular < operator.
   *
   * For example, it maps the string "2.3.17~20131103" to the tuple:
       ([2; 3; 17], 20131103)
   *
   * This function parses for the moment version numbers like:

       epoch:ver.rev.level~add-patch

     where each placeholder can be an integer. The only mandatory part
     is the dot-separated list in the middle (which may have any
     arbitrary length).

     The resulting tuple would be:

       (epoch, [ver; rev; level], add, patch)
   *)
  let parse_version v =
    (* Get a matched group, or return a default value if the group does
     * not exist. *)
    let def_group def n s =
      try Str.matched_group n s
      with Not_found -> def
    in

    let rever = Str.regexp "^\\(\\([0-9]+\\):\\)?\\([0-9.]+\\)\\(~\\([0-9]+\\)\\)?\\(-\\([0-9]+\\)\\)?$" in
    let _ = Str.string_match rever v 0 in
    let epoch = def_group "0" 2 v
    and main  = def_group ""  3 v
    and additional = def_group "0" 5 v
    and last = def_group "0" 7 v in

    (* Actually build the version tuple *)
    (
      (* Epoch *)
      int_of_string epoch,
      (* Main part of the version number: we have a dot-separated list
       * of integers. *)
      List.map int_of_string (Str.split (Str.regexp "\\.") main),
      (* Additional part after ~ *)
      int_of_string additional,
      (* Last part, after - *)
      int_of_string last
    )
  in
  let installed = Findlib.package_property [] alias "version" in
  let min_ver_list = parse_version min_version
  and ins_ver_list = parse_version installed in
  if min_ver_list <= ins_ver_list then
    true
  else
    (
      Printf.printf "%s is too old: version %s requested, but %s has been found\n"
        package min_version installed;
      false
    )

let patoline_uses_packages =
  let res = Hashtbl.create 10 in
  let packs =
    [ fl_package "zip"         ["camlzip"]
    ; fl_package "cairo"       ["ocaml-cairo"]
    ; fl_package "lablgl"      ["lablGL"]
    ; fl_package "lablgl.glut" ["lablGL.glut"]
    ; { fl_package_name     = "fontconfig"
      ; fl_known_aliases    = []
      ; fl_additional_check =
          let f package alias =
            let fontconfig_min_version = "0~20131103" in
            if Findlib.package_property [] alias "version" = "0.1" then
              begin
                Printf.printf "Update fontconfig to version %s\n"
                fontconfig_min_version; false
              end
            else package_min_version fontconfig_min_version package alias
          in
          Some (f, "version >= 0~20131103") } ]
  in
  List.iter (fun p -> Hashtbl.add res p.fl_package_name p) packs; res

let ocamlfind_query =
  let checked = Hashtbl.create 10 in
  let query pack =
    if is_local_package pack then (true, pack) else
    try Hashtbl.find checked pack
    with Not_found ->
      Printf.printf "Looking for package %s..." pack;
      let (names, opt_check) =
        try
          let p = Hashtbl.find patoline_uses_packages pack in
          (p.fl_package_name :: p.fl_known_aliases, p.fl_additional_check)
        with Not_found -> ([pack], None)
      in
      let f res alias =
        if fst res then res else
        try
          let _ = Findlib.package_directory alias in
          match opt_check with
          | None       -> (true, alias)
          | Some (c,m) -> if c pack alias then (true, alias) else res
        with _ -> res
      in
      let res = List.fold_left f (false, "") names in
      Hashtbl.add checked pack res;
      if fst res then Printf.printf " found (%s)\n" (snd res)
      else Printf.printf " not found\n";
      res
  in query

(* Is a package ocamlfindable? *)
let ocamlfind_has pack = is_local_package pack || fst (ocamlfind_query pack)

(* Listing Patoline drivers with their corresponding dependancies.
 * A driver may depend on some package found using ocamlfind, or on some other
 * driver. *)
type driver_needs = Package of string | Driver of driver

and driver =
  (* Driver module name. *)
  { name      : string
  (* List of required packages to build the driver. *)
  ; needs     : driver_needs list
  (* List of optional packages, which improve the driver when present. *)
  ; suggests  : driver_needs list
  (* List of local packages (not installed system-wide while building
     Patoline) needed to output a document using this driver. The code
     package does not need to be specified, as it is always added. *)
  ; internals : driver_needs list }

let patoline_driver_gl =
  { name      = "DriverGL"
  ; needs     = [ Package "str" ; Package "imagelib"; Package "zip";
		  Package "lablgl" ; Package "lablgl.glut"]
  ; suggests  = []
  ; internals = [Package "Typography" ; Package "db" ] }

let patoline_driver_image =
  { name      = "DriverImage"
  ; needs     = [ Package "lablgl" ; Package "lablgl.glut" ; Package "imagelib" ]
  ; suggests  = []
  ; internals = [Driver patoline_driver_gl; Package "Typography" ] }

let svg_driver =
  { name      = "SVG"
  ; needs     = []
  ; suggests  = []
  ; internals = [Package "Typography"; Package "db"] }

let all_patoline_drivers =
  [ { name      = "None"
    ; needs     = []
    ; suggests  = []
    ; internals = [] }

  ; { name      = "Pdf"
    ; needs     = []
    ; suggests  = [Package "zip"]
    ; internals = [Package "Typography"] }

  ; { name      = "Bin"
    ; needs     = []
    ; suggests  = []
    ; internals = [Package "Typography"] }

  ; { name      = "Html"
    ; needs     = []
    ; suggests  = []
    ; internals = [Package "Typography"; Package "unicodelib"] }

  ; { name      = "Patonet"
    ; needs     = [Package "cryptokit"]
    ; suggests  = []
    ; internals = [Package "Typography"; Driver svg_driver] }

  ; { name      = "DriverCairo"
    ; needs     = [ Package "cairo"]
    ; suggests  = []
    ; internals = [Package "Typography"] }

  ; { name      = "Net"
    ; needs     = []
    ; suggests  = []
    ; internals = [Package "Typography"; Driver svg_driver] }

  ; { name      = "Web"
    ; needs     = []
    ; suggests  = []
    ; internals = [Package "Typography"; Driver svg_driver] }

  ; svg_driver
  ; patoline_driver_gl
  ; patoline_driver_image ]

let patoline_drivers =
  let pred d = not (List.mem d.name !driver_blist) in
  List.filter pred all_patoline_drivers

let find_driver name =
  try List.find (fun p -> name = p.name) patoline_drivers
  with Not_found ->
    Printf.printf "Did not find driver \"%s\"...\n%!" name;
    raise Not_found

let includes_driver ?(subdir_only=true) name =
  let add d acc = if List.mem d acc then acc else d::acc in
  let rec fn acc name =
    match name with
    | Driver p ->
       let acc = if false && subdir_only then acc else
	 add ("-I "^(Filename.concat (Filename.concat "src" "Drivers") p.name)) acc
       in
       let acc = List.fold_left fn acc p.internals in
       acc

    | Package name ->
       List.fold_left (fun acc x -> add x acc) acc (includes_local_list ~subdir_only name)
  in String.concat " " (fn [] (Driver name))


(* Checks whether we can build a given driver.
 * This certainly won't check that a driver doesn't somehow reference itself:
 * expect infinite loops if you do not care. *)
let rec can_build_driver d =
  let check_need = function
    | Package p -> ocamlfind_has p
    | Driver d' -> can_build_driver d'
  in List.iter (fun a -> ignore (check_need a)) d.suggests;
  let found, missing = List.partition check_need d.needs in
  if List.exists (fun x->x.name==d.name) patoline_drivers && missing = []
  then true
  else (
    Printf.eprintf "Warning: driver %s not build because %s are missing\n"
      d.name
      (String.concat ", " (List.filter (fun s -> String.length s > 0) (List.map (function
      | Package pack  ->
        (try
           let n = Hashtbl.find patoline_uses_packages pack in
           n.fl_package_name ^ " " ^ (match n.fl_additional_check with None ->
             "" | Some (_,m) -> m)
         with
           _ -> pack)
      | Driver d -> d.name ^ " driver") missing)));
    false
  )

(* Generates contents for a -package option for ocamlfind, using the argument
 * needs.
 * This function does not require all packages in "needs" to be present. If some
 * of them are missing, they simply won't appear in the returned string.
 *)
let gen_pack_line ?(query=true) needs =
  let rec aux_gen = function
  | [] -> []
  | (Package p) :: needs ->
      (if query then (snd (ocamlfind_query p)) else p) :: (aux_gen needs)
  | (Driver d) :: needs ->
      ("Typography."^d.name) :: (aux_gen d.needs) @ (aux_gen d.suggests) @ (aux_gen needs)
  in (List.filter ((<>) "") (aux_gen needs))

let _=
  let has_mysql      = ocamlfind_has "mysql" in
  let has_sqlite3    = ocamlfind_has "sqlite3" in
  let has_fontconfig = ocamlfind_has "fontconfig" in

  if not has_mysql then
    Printf.eprintf "Warning: package mysql missing, \
                    Patonet will not support Mysql storage\n";

  if not has_sqlite3 then
    Printf.eprintf "Warning: package sqlite3 missing, \
                    Patonet and Bibi will not support sqlite storage\n";

  if not has_fontconfig then
    Printf.eprintf "Warning: fontconfig is missing, \
                    patoline will not use it to search for fonts\n";

  let emacsdir = Filename.concat !prefix "share/emacs/site-lisp/patoline" in

  (* Generation of src/Makefile.config *)
  let make = open_out "src/Makefile.config" in

  Printf.fprintf make "OCPP := cpp -C -ffreestanding -w %s%s%s%s%s%s%s\n"
    (if Sys.word_size = 32  then "-DINT32 " else "")
    (if ocamlfind_has "zip" then "-DCAMLZIP " else "")
    (if has_mysql then "-DMYSQL " else "")
    (if has_sqlite3 then "-DSQLITE3 " else "")
    (if !ban_comic_sans then "-DBAN_COMIC_SANS " else "")
    (if !pdf_type3_only then "-DPDF_TYPE3_ONLY " else "")
    (if !lang <> "EN" then ("-DLANG_" ^ (!lang)) else "");

  Printf.fprintf make "CAMLZIP :=%s\n"
    (if ocamlfind_has "zip" then " " ^ (snd (ocamlfind_query "zip")) else "");

  List.iter (function { package_name = name; macro_suffix = macro; local_deps = local; extern_deps = extern } ->
    let f = List.map (fun x->Package x) in
    let h x = if x = "" then "" else "-package " ^ x in
    Printf.fprintf make "PACK_%s := %s %s\n"
      macro (h
      (String.concat "," (gen_pack_line (f (packages_local local) @ f extern))))
      (includes_local name);
    Printf.fprintf make "DEPS_PACK_%s := %s %s\n"
      macro (includes_local ~subdir_only:false name) (h
      (String.concat "," (gen_pack_line (f extern)))))
    local_packages;

  Printf.fprintf make "INSTALL_FONT_DIR :=%s\n" !fonts_dir;
  Printf.fprintf make "INSTALL_GRAMMARS_DIR :=%s\n" !grammars_dir;
  Printf.fprintf make "INSTALL_HYPHEN_DIR :=%s\n" !hyphen_dir;
  Printf.fprintf make "INSTALL_TYPOGRAPHY_DIR :=%s/Typography\n" !ocaml_lib_dir;
  Printf.fprintf make "INSTALL_DRIVERS_DIR :=%s\n" !driver_dir;
  Printf.fprintf make "INSTALL_DLLS_DIR :=%s\n" !ocaml_dlls_dir;
  Printf.fprintf make "INSTALL_EMACS_DIR :=%s\n" emacsdir;
  Printf.fprintf make "INSTALL_RBUFFER_DIR :=%s/rbuffer\n" !ocaml_lib_dir;
  Printf.fprintf make "INSTALL_UTIL_DIR :=%s/patutil\n" !ocaml_lib_dir;
  Printf.fprintf make "INSTALL_RAWLIB_DIR :=%s/rawlib\n" !ocaml_lib_dir;
  Printf.fprintf make "INSTALL_DB_DIR :=%s/db\n" !ocaml_lib_dir;
  Printf.fprintf make "INSTALL_UNICODELIB_DIR :=%s/unicodelib\n" !ocaml_lib_dir;
  Printf.fprintf make "INSTALL_LIBFONTS_DIR :=%s/patfonts\n" !ocaml_lib_dir;
  Printf.fprintf make "INSTALL_BIBI_DIR :=%s/bibi\n" !ocaml_lib_dir;
  Printf.fprintf make "INSTALL_PATOPLOT_DIR :=%s/patoplot\n" !ocaml_lib_dir;
  Printf.fprintf make "INSTALL_PLUGINS_DIR :=%s\n" !plugins_dir;
  Printf.fprintf make "INSTALL_CESURE_DIR :=%s/cesure\n" !ocaml_lib_dir;

  Printf.fprintf make "INSTALL_BIN_DIR :=%s\n" !bindir;

  Printf.fprintf make "PREFIX :=%s\n" !prefix;

  (* Write out the list of enabled drivers *)
  let ok_drivers = List.filter can_build_driver patoline_drivers in
  Printf.fprintf make "DRIVERS := %s\n"
    (String.concat " "
      (List.map (fun d -> d.name) ok_drivers)
    );

  let has_patonet = List.exists (fun d -> d.name = "Patonet") ok_drivers in

  (* Output -package option for enabled drivers *)
  List.iter
  (fun d ->
    let pack = String.concat "," (gen_pack_line (d.internals @ d.needs @ d.suggests)) in
    let pack = if pack <> "" then "-package "^pack else pack in
    Printf.fprintf make "PACK_DRIVER_%s := %s %s\n" d.name pack
      (includes_driver d);
    Printf.fprintf make "DEPS_PACK_DRIVER_%s := %s %s\n"d.name pack
      (includes_driver ~subdir_only:false d)
  )
  ok_drivers;

  (* Enable compilation of pa_patoline if pa_ocaml is installed *)
  Printf.fprintf make "PA_PATOLINE := %s\n" "src/patobuild/pa_patoline";

  (* Tell make which ConfigFindFont (fontconfig or not) should be linked while
   * building Typograhy.cmxa. *)
  Printf.fprintf make "FINDFONT := %s\n" (if has_fontconfig then "ConfigFindFontFC" else "ConfigFindFontLeg");
  Printf.fprintf make "FONTCONFIG_CMXA := %s\n" (if has_fontconfig then "camlfontconfig.cmxa" else "");
  close_out make;

  (* Generate a .META file for the driver n with internal / external dependency intd / extd *)
  let driver_generated_metas = ref [] in
  let gen_meta_driver drv =
    if can_build_driver drv then begin
      let meta_name = "src/Drivers/" ^ drv.name ^ "/" ^ drv.name ^ ".META" in
      driver_generated_metas := meta_name :: !driver_generated_metas;
      let f = open_out meta_name in
        Printf.fprintf f "package \"%s\" (\n" drv.name;
        Printf.fprintf f "archive(byte)=\"%s.cma\"\n" drv.name;
        Printf.fprintf f "archive(native)=\"%s.cmxa\"\n" drv.name;
        let alldep = (gen_pack_line ~query:false (Package "Typography" :: drv.internals)) @ (gen_pack_line drv.needs) @ (gen_pack_line drv.suggests) in
        Printf.fprintf f "requires=\"%s\"\n" (String.concat "," alldep);
        Printf.fprintf f ")\n";
        close_out f
    end
  in
  List.iter gen_meta_driver patoline_drivers;

  (* Generate the META file for Typography, which details package information
   * for Typography.cmxa/Typography.cma as well as subpackages for each format.
   * Each format in the source tree can be shipped with a custom FormatName.META
   * file, which is included as is. Otherwise, a generic entry is generated for
   * the format.
   *
   *)
  let meta=open_out "src/Typography/META" in
    Printf.fprintf meta
      "name=\"Typography\"\nversion=\"0.1\"\ndescription=\"Typography library\"\nrequires=\"patutil,patfonts,%s\"\n"
      (* FIXME: the line below should be generated from Typography deps !!!*)
      (String.concat "," (gen_pack_line [Package "str"; Package "unicodelib"; Package "rawlib"; Package "mysql";
                                         Package "zip";
                                         Package "imagelib";Package "dynlink";
                                         Package "fontconfig"; Package
                                         "cesure"; Package
                                         "db"]));
    Printf.fprintf meta "archive(native)=\"patoconfig.cmxa Typography.cmxa, DefaultFormat.cmxa\"\n";
    Printf.fprintf meta "archive(byte)=\"patoconfig.cma Typography.cma, DefaultFormat.cmx\"\n";

  let check_name file=
    let valid=ref (String.length file>0) in
    for i=0 to String.length file-1 do
      valid:= !valid && ((file.[i]>='a' && file.[i]<='z')
                         || (file.[i]>='A' && file.[i]<='Z')
                         || (file.[i]>='0' && file.[i]<='9'))
    done;
    !valid
  in
  let make_meta_part dir file =
    if Filename.check_suffix file ".ml" && check_name (Filename.chop_extension file)
    then (
      let base_file = Filename.chop_extension file in
      let custom_meta = Filename.concat dir (base_file^".META") in
      try
        let custom_meta_fd = open_in custom_meta in
        let custom_meta_len = in_channel_length custom_meta_fd in
        let buf = Bytes.create custom_meta_len in
        really_input custom_meta_fd buf 0 custom_meta_len;
        close_in custom_meta_fd;
        Printf.fprintf meta "%s\n" buf
      with Sys_error _ ->
        Printf.fprintf meta
          "package \"%s\" (\nrequires=\"rawlib,Typography\"\narchive(native)=\"%s\"\narchive(byte)=\"%s\"\n)\n"
          base_file (base_file^".cmxa") (base_file^".cma")
    )
  in
  let is_substring s1 s0 =
    let rec sub i j=
      if i>String.length s0-String.length s1 then false else
        if j>=String.length s1 then true else
          if s0.[i+j]=s1.[j] then sub i (j+1) else
            sub (i+1) 0
    in sub 0 0
  in
  Array.iter
    (fun file ->
      if (is_substring "Format" file || file = "Interactive.ml") (*&& file <> "DefaultFormat.ml"*)
      then make_meta_part "src/Format" file) (Sys.readdir "src/Format");
  List.iter (fun drv ->
    make_meta_part (Filename.concat "src/Drivers" drv.name) (drv.name ^ ".ml")
  ) patoline_drivers;
  close_out meta;

  (* Rules.clean tells GNUmakefile which files have been generated. *)
  let clean = open_out "Rules.clean" in
  let metas = String.concat " " !driver_generated_metas in
  Printf.fprintf clean "DISTCLEAN += Rules.clean src/Typography/META ";
  Printf.fprintf clean "src/Makefile.config %s\n" metas;
  close_out clean;

  (* Generation of config. *)
  let open Printf in
  let plist oc l = List.iter (fprintf oc "%S;") l in
  let oc = open_out "src/config/patDefault.ml" in
  fprintf oc "let fonts_dir          = %S\n" !fonts_dir;
  fprintf oc "let plugins_dir        = %S\n" !plugins_dir;
  fprintf oc "let grammars_dir       = %S\n" !grammars_dir;
  fprintf oc "let hyphen_dir         = %S\n" !hyphen_dir; 
  fprintf oc "let extra_fonts_dir    = [%a]\n" plist (List.tl !fonts_dirs);
  fprintf oc "let extra_plugins_dir  = [%a]\n" plist (List.tl !plugins_dirs);
  fprintf oc "let extra_grammars_dir = [%a]\n" plist (List.tl !grammars_dirs);
  fprintf oc "let extra_hyphen_dir   = [%a]\n" plist (List.tl !hyphen_dirs);
  let drivers = List.map (fun d -> d.name) ok_drivers in
  fprintf oc "let drivers            =\n  [%a]\n" plist drivers;
  fprintf oc "let has_patonet        = %b\n" has_patonet;
  close_out oc
