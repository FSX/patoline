open CamomileLibrary
open Typography
open Typography.Util
open Typography.Fonts
open Typography.Fonts.FTypes
open Typography.OutputCommon
open Typography.OutputPaper


type font_cache={
  subfonts:(Fonts.font * (FTypes.glyph_id*int) IntMap.t) StrMap.t;
  mutable instances:(int StrMap.t) StrMap.t;
  classes:string StrMap.t
}

let build_font_cache pages=
  let rec make_fonts i l fonts=
    match l with
        []->(
          if i+1>=Array.length pages then fonts else (
            make_fonts (i+1) (pages.(i+1)) fonts
          )
        )
      | Glyph h::s->(
        let font=Fonts.glyphFont h.glyph in
        let fontName=(Fonts.uniqueName font) in
        let _,fontDict=
          try StrMap.find fontName fonts with
              Not_found->font,IntMap.empty
        in
        let num=Fonts.glyphNumber h.glyph in
        let c=UChar.code (UTF8.look num.glyph_utf8 0) in
        (* map de tous les caractères commençant par c *)
        let beginning_with_c=try IntMap.find c fontDict with Not_found->IntMap.empty in
        let beginning_with_c'=
          if IntMap.mem num.glyph_index beginning_with_c then
            beginning_with_c
          else
            IntMap.add num.glyph_index (num, IntMap.cardinal beginning_with_c)
              beginning_with_c
        in
        let fonts'=StrMap.add fontName (font,(IntMap.add c (beginning_with_c') fontDict)) fonts in
        make_fonts i s fonts'
      )
      | _::s->make_fonts i s fonts
  in
  let f=make_fonts (-1) [] StrMap.empty in
  (* Il faut fusionner les maps de tous les glyphes utilisés, pour ne
     plus les distinguer par premier caractère *)
  let f=StrMap.map (fun (font,a)->
    (font,
     IntMap.fold (fun char glyphMap m->
       IntMap.fold (fun glyphIdx (gl,subfont) n->
         IntMap.add glyphIdx (gl,subfont) n
       ) glyphMap m) a IntMap.empty)
  ) f
  in

  (* Eviter que deux fonts avec le même nom et des fichiers différents ne s'emmèlent *)
  let fontInstances=ref StrMap.empty in
  let fontInstance font=
    let u=Fonts.uniqueName font in
    let p=(Fonts.fontName font).postscript_name in
    let instances=try StrMap.find p !fontInstances with Not_found->StrMap.empty in
    let inst_num=try StrMap.find u instances with Not_found->StrMap.cardinal instances in
    fontInstances:=StrMap.add p (StrMap.add u inst_num instances) !fontInstances;
    inst_num
  in

  let style_buf=Rbuffer.create 256 in
  Rbuffer.add_string style_buf "body{line-height:0;}\n.z { font-size:0; }\n";
  let classes=ref StrMap.empty in
  StrMap.iter (fun name (font,a)->
    (* k : nom de la police
       a : (glyph*int) IntMap.t : map du numéro de glyph vers la sous-police *)
    let sub_fonts=
      IntMap.fold (fun glyphIdx (gl,subfont) n->
        let glyphs=try IntMap.find subfont n with Not_found->[] in
        IntMap.add subfont (gl::glyphs) n
      ) a IntMap.empty
    in
    IntMap.iter (fun subfont glyphList->
      let glyphList=
        ({glyph_index=0;glyph_utf8="" })::glyphList
      in
      let glyphs=Array.of_list glyphList in
      let instance=fontInstance font in

      let full=(Fonts.fontName font).postscript_name^"_"^(string_of_int instance)^"_"^(string_of_int subfont) in
      let info=Fonts.fontInfo font in
      let filename=full^".otf" in
      (* Fonts.setName info *)
      (*   { family_name=family; *)
      (*     subfamily_name=subfamily; *)
      (*     full_name=full; *)
      (*     postscript_name=ps }; *)
      let class_name=Printf.sprintf "c%d" (StrMap.cardinal !classes) in
      classes:=StrMap.add (full) class_name !classes;
      let rec make_bindings i b=
        if i>=Array.length glyphs then b else (
          let gl=glyphs.(i) in
          make_bindings (i+1)
            (if UTF8.out_of_range gl.glyph_utf8 0 then b else
                IntMap.add (UChar.code (UTF8.look gl.glyph_utf8 0)) i b)
        )
      in
      let buf=Fonts.subset font info (make_bindings 1 IntMap.empty) glyphs in
      let out=open_out filename in
      Rbuffer.output_buffer out buf;
      close_out out;
    ) sub_fonts
  ) f;
  { subfonts=f;
    instances= !fontInstances;
    classes= !classes }

(* renvoit (nom complet de la police, nom de la classe) *)
let className cache gl=
  let font=Fonts.glyphFont gl in
  let idx=Fonts.glyphNumber gl in
  let u=Fonts.uniqueName font in
  let _,subfont=IntMap.find idx.glyph_index (snd (StrMap.find u cache.subfonts)) in

  (* fontInstances *)
  let p=(Fonts.fontName font).postscript_name in
  let instances=try StrMap.find p cache.instances with Not_found->StrMap.empty in
  let inst_num=try StrMap.find u instances with Not_found->StrMap.cardinal instances in
  cache.instances<-StrMap.add p (StrMap.add u inst_num instances) cache.instances;
  let instance=inst_num in
  (*  *)

  let full=(Fonts.fontName font).postscript_name^"_"^(string_of_int instance)^"_"^(string_of_int subfont) in
  (full,StrMap.find full cache.classes)

let make_style cache=
  let style_buf=Rbuffer.create 256 in
  StrMap.iter (fun full class_name->
    Rbuffer.add_string style_buf (Printf.sprintf "@font-face { font-family:%s;
src:url(\"%s.otf\") format(\"opentype\"); }
.%s { font-family:%s; }\n"
                                    class_name full class_name class_name)
  ) cache.classes;
  style_buf