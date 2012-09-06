open FTypes
open Util
open CFF
open CamomileLibrary
let offsetTable=12
let dirSize=16
exception Table_not_found of string

type font = CFF of (CFF.font*int)

let tableLookup table file off=
  seek_in file (off+4);
  let numTables=readInt2 file in
  let tableName="    " in
  let rec lookup i j=
    let middle=(i+j) / 2 in
      seek_in file (off+offsetTable+middle*dirSize);
      really_input file tableName 0 4;
      if middle<=i then
        if tableName=table then
          ((seek_in file (off+offsetTable+i*dirSize+8);readInt4 file),
           (seek_in file (off+offsetTable+i*dirSize+12);readInt4 file))
        else
          raise (Table_not_found table)
      else
        if compare tableName table <=0 then
          lookup middle j
        else
          lookup i middle
  in
    lookup 0 numTables

let tableList file off=
  seek_in file (off+4);
  let numTables=readInt2 file in
  let rec getTables n l=
    if n=offsetTable then l else
      (seek_in file (off+n);
       let newTable=String.create 4 in
         really_input file newTable 0 4;
         getTables (n-dirSize) (newTable::l))
  in
    getTables (off+dirSize*(numTables-1)+offsetTable) []

let loadFont ?offset:(off=0) ?size:(_=0) file=
  let f=open_in_bin_cached file in
  let typ=String.create 4 in
    seek_in f off;
    really_input f typ 0 4;
    match typ with
        "OTTO"->
          let (a,b)=tableLookup "CFF " f off in
            CFF (CFF.loadFont file ~offset:(off+a) ~size:b, off)
      | _->failwith ("OpenType : format non reconnu : "^typ)

let fontName ?index:(idx=0) f =
  match f with
      CFF (x,_)->CFF.fontName x ~index:idx

let cardinal=function
    CFF (f,_)->CFF.cardinal f


type glyph = CFFGlyph of (font*CFF.glyph)

let glyph_of_uchar font0 char0=
  match font0 with
      CFF (font,offset0)->
        let file=open_in_bin_cached font.file in
        let char=UChar.code char0 in
        let (a,b)=tableLookup "cmap" file offset0 in
        seek_in file (a+2);
        let numTables=readInt2 file in

        let rec read_tables table=
          if table>=numTables then 0 else (
            seek_in file (a+8+8*table);
            let offset=a+readInt4 file in
            seek_in file offset;
            let t=readInt2 file in
            (match t with
                0->if char<256 then (
                  seek_in file (offset+6+char);
                  let cid=input_byte file in
                  if cid<>0 then cid else read_tables (table+1)
                ) else read_tables (table+1)
              | 2->
                (let i=(char lsr 8) land 0xff in
                 let j=char land 0xff in
                 let k=(seek_in file (offset+6+i*2); readInt2 file) lsr 3 in
                 let subHeaders=offset+6+256*2+k*8 in
                 if k=0 then
                   (seek_in file (subHeaders+6);
                    let idRangeOffset=readInt2 file in
                    seek_in file (subHeaders+idRangeOffset+i*2);
                    let cid=readInt2 file in
                    if cid<>0 then cid else read_tables (table+1)
                   )
                 else
                   (let firstCode=seek_in file subHeaders; readInt2 file in
                    let entryCount=seek_in file (subHeaders+2); readInt2 file in
                    let idDelta=seek_in file (subHeaders+4); readInt file 2 in
                    let idDelta=if idDelta>=0x8000 then idDelta-0x8000 else idDelta in
                    let idRangeOffset=seek_in file (subHeaders+6); readInt2 file in
                    if j>=firstCode && j < (firstCode+entryCount) then
                      (let p=seek_in file (subHeaders+8+idRangeOffset+j*2); readInt2 file in
                       let cid=if p=0 then p else p+idDelta in
                       if cid<>0 then cid else read_tables (table+1))
                    else
                      read_tables (table+1)
                   )
                )
              | 4->(
                let sc2=seek_in file (offset+6); readInt2 file in
                let rec smallestEnd i j=
                  if j<=i then i else
                    let middle=((i+j) lsr 1) land 0xfffe in
                    let end_=seek_in file (offset+14+middle); readInt2 file in
                    if char>end_ then
                      smallestEnd (middle+2) j
                    else
                      smallestEnd i middle
                in
                let seg=smallestEnd 0 (sc2-2) in
                let start=seek_in file (offset+16+sc2+seg); readInt2 file in
                if char>=start then (
                  let delta=seek_in file (offset+16+2*sc2+seg); readInt2 file in
                  let delta=if delta>=0x8000 then delta-0x8000 else delta in
                  let p_idrOffset=offset+16+3*sc2+seg in
                  let idrOffset=seek_in file p_idrOffset; readInt2 file in
                  let cid=
                    if idrOffset=0 then
                      (char+delta) mod 0x8000
                    else (
                      seek_in file (idrOffset+2*(char-start)+p_idrOffset);
                      (readInt2 file+delta) mod 0x8000
                    )
                  in
                  if cid<>0 then cid else read_tables (table+1)
                ) else read_tables (table+1)
              )
              | 6->
                (seek_in file (offset+6);
                 let first=readInt2 file in
                 let entryCount=readInt2 file in
                 if first<=char && char <first+entryCount then
                   (seek_in file (offset+10+(char-first)*2);
                    let cid=readInt2 file in
                    if cid<>0 then cid else read_tables (table+1))
                 else
                   read_tables (table+1)
                )
              | _->read_tables (table+1)
            ))
        in
        let cid=read_tables 0 in
        if cid = 0 then
          raise (Glyph_not_found (fontName font0, UTF8.init 1 (fun _->char0)))
        else
          cid

let glyph_of_char f c=glyph_of_uchar f (UChar.of_char c)


let glyphFont f=match f with
    CFFGlyph (x,_)->x
let loadGlyph f ?index:(idx=0) gl=
  match f with
      CFF (x,_)->CFFGlyph (f, CFF.loadGlyph x ~index:idx gl)
let outlines gl=match gl with
    CFFGlyph (_,x)->CFF.outlines x
let glyph_y0 gl=match gl with
    CFFGlyph (_,x)->CFF.glyph_y0 x
let glyph_y1 gl=match gl with
    CFFGlyph (_,x)->CFF.glyph_y1 x

let glyph_x0 gl=match gl with
    CFFGlyph (_,x)->CFF.glyph_x0 x
let glyph_x1 gl=match gl with
    CFFGlyph (_,x)->CFF.glyph_x1 x

let glyphNumber gl=match gl with
    CFFGlyph (_,x)->CFF.glyphNumber x

let glyphContents gl=match gl with
    CFFGlyph (_,x)->CFF.glyphContents x

let glyphName gl=
  match gl with
      CFFGlyph (CFF(f, offset),x)-> CFF.glyphName x


let glyphWidth gl=
  match gl with
      CFFGlyph (_,x) when x.glyphWidth <> infinity -> x.glyphWidth
    | CFFGlyph (CFF(f, offset),x)->
        (let file=open_in_bin_cached f.CFF.file in
         let num=(CFF.glyphNumber x).glyph_index in
         let (a,_)=tableLookup "hhea" file offset in
         let nh=(seek_in file (a+34); readInt2 file) in
         let (b,_)=tableLookup "hmtx" file offset in
           seek_in file (if num>=nh then (b+4*(nh-1)) else (b+4*num));
           let w=float_of_int (readInt2 file) in
             x.glyphWidth<-w;
             w
        )

let otype_file font=match font with
    CFF (font,offset0)->font.file, offset0


let coverageIndex file off glyph=
  let format=seek_in file off; readInt2 file in
  let count=readInt2 file in
  let rec format1 x0 x1=
    if x0>=x1 then raise Not_found else
      if x1=x0+1 then
        (let x2=(x0+x1)/2 in
         let current=seek_in file (off+4+2*x2); readInt2 file in
           if current=glyph then x2 else raise Not_found)
      else
        (let x2=(x0+x1)/2 in
         let current=seek_in file (off+4+2*x2); readInt2 file in
           if glyph<current then format1 x0 x2 else format1 x2 x1)
  in
  let rec format2 x0 x1=
    if x0>=x1 then raise Not_found else
      if x1=x0+1 then
        (let start=seek_in file (off+6*x0+4); readInt2 file in
         let final=readInt2 file in
         let cvIdx=readInt2 file in
           if glyph>=start && glyph<=final then
             cvIdx+glyph-start
           else
             raise Not_found)

      else
        (let x2=(x0+x1)/2 in
         let final=seek_in file (off+6*x0+6); readInt2 file in
           if glyph>final then
             format2 x2 x1
           else
             format2 x0 x2)
  in
    if format=1 then format1 0 count else
      if format=2 then format2 0 count else
        (Printf.printf "format : %d\n" format; raise Not_found)


let class_def file off glyph=
  let format=seek_in file off; readInt2 file in
    if format=1 then (
      let startGlyph=readInt2 file in
      let glyphCount=readInt2 file in
        if glyph>=startGlyph && glyph<startGlyph+glyphCount then
          (seek_in file (off+6+2*(glyph-startGlyph)); readInt2 file)
        else
          0
    ) else if format=2 then (
      let classRangeCount=readInt2 file in
      let off0=off+4 in
      let rec format2 x0 x1=
        let x2=(x0+x1)/2 in
        let rstart=seek_in file (off0+6*x2); readInt2 file in
        let rend=readInt2 file in
          if glyph<rstart then
            if x1-x0<=1 then 0 else format2 x0 x2
          else
            if glyph>rend then
              if x1-x0<=1 then 0 else format2 x2 x1
            else
              readInt2 file
      in
        format2 0 classRangeCount
    ) else 0

(************* Layout tables : GSUB, GPOS, etc. ***************)

let readCoverageIndex file off=
  let format=seek_in file off; readInt2 file in
  let count=readInt2 file in
  let rec format1 i result=
    if i>=count then result else (
      let c=readInt2 file in
        format1 (i+1) ((c,i)::result)
    )
  in
  let rec format2 i result=

    if i>=count then result else (
      let start=readInt2 file in
      let final=readInt2 file in
      let cvIdx=readInt2 file in
      let rec make_range i result=
        if i>final then result else (
          make_range (i+1) ((i,i+cvIdx-start)::result)
        )
      in
        format2 (i+1) (make_range start result)
    )
  in
    if format=1 then format1 0 [] else
      if format=2 then format2 0 [] else
        []

let readClass file off=
  let format=seek_in file off; readInt2 file in
    if format=1 then (
      let startGlyph=readInt2 file in
      let glyphCount=readInt2 file in
      let rec classValues i result=if i>=glyphCount then List.rev result else
        (classValues (i-1) ((startGlyph+i, readInt2 file)::result))
      in
        classValues 0 []
    ) else if format=2 then (
      let classRangeCount=readInt2 file in
      let rec format2 i result=
        if i>=classRangeCount then result else (
          let startGlyph=readInt2 file in
          let endGlyph=readInt2 file in
          let cl=readInt2 file in
          let rec make_range i r= if i>endGlyph then r else (make_range (i+1) ((i,cl)::r)) in
            format2 (i+1) (make_range startGlyph result)
        )
      in
        format2 0 []
    ) else []
(*********************************)


#define GSUB_SINGLE 1
#define GSUB_MULTIPLE 2
#define GSUB_ALTERNATE 3
#define GSUB_LIGATURE 4
#define GSUB_CONTEXT 5
#define GSUB_CHAINING 6


let rec readLookup file gsubOff i=
  let subst=ref [] in
  let lookup= seek_in file (gsubOff+8); readInt2 file in
  let offset0=seek_in file (gsubOff+lookup+2+i*2); gsubOff+lookup+(readInt2 file) in

  let lookupType=seek_in file offset0; readInt2 file in
    (* let lookupFlag=seek_in file (offset0+2); readInt2 file in *)
  let subtableCount=seek_in file (offset0+4); readInt2 file in
    for subtable=0 to subtableCount-1 do
      let offset1=seek_in file (offset0+6+subtable*2); offset0+(readInt2 file) in

        match lookupType with
            GSUB_SINGLE->(
              let format=seek_in file offset1;readInt2 file in
              let coverageOff=readInt2 file in
                if format=1 then (
                  let delta=readInt2 file in
                  let cov=readCoverageIndex file (offset1+coverageOff) in
                    List.iter (fun (a,_)->subst:=(Subst { original_glyphs=[|a|]; subst_glyphs=[|a+delta|]})::(!subst)) cov
                ) else if format=2 then (
                  let cov=readCoverageIndex file (offset1+coverageOff) in
                    List.iter (fun (a,b)->
                                 let gl=seek_in file (offset1+6+b*2); readInt2 file in
                                   subst:=(Subst { original_glyphs=[|a|]; subst_glyphs=[|gl|]})::(!subst)) cov
                )
            )
          | GSUB_MULTIPLE->(
              let coverageOff=seek_in file (offset1+2); readInt2 file in
              let cov=readCoverageIndex file (offset1+coverageOff) in
                List.iter (fun (first_glyph,alternate)->
                             let offset2=seek_in file (offset1+6+alternate*2); offset1+readInt2 file in
                             let glyphCount=seek_in file offset2; readInt2 file in
                             let arr=Array.make glyphCount 0 in
                               for comp=0 to glyphCount-1 do
                                 arr.(comp)<-readInt2 file;
                               done;
                               subst:=(Subst { original_glyphs=[|first_glyph|]; subst_glyphs=arr})::(!subst)
                          ) cov
            )
          | GSUB_ALTERNATE->(
              let coverageOff=seek_in file (offset1+2); readInt2 file in
              let cov=readCoverageIndex file (offset1+coverageOff) in
                List.iter (fun (first_glyph,alternate)->
                             let offset2=seek_in file (offset1+6+alternate*2); offset1+readInt2 file in
                             let glyphCount=seek_in file offset2; readInt2 file in
                             let arr=Array.make (1+glyphCount) first_glyph in
                               for comp=1 to glyphCount do
                                 arr.(comp)<-readInt2 file;
                               done;
                               subst:=(Alternative arr)::(!subst)
                          ) cov
            )
          | GSUB_LIGATURE->(
              let coverageOff=seek_in file (offset1+2); readInt2 file in
              let cov=readCoverageIndex file (offset1+coverageOff) in
                (* let ligSetCount=seek_in file (offset1+4); readInt2 file in *)
                List.iter (fun (first_glyph,ligset)->
                             (* for ligset=0 to ligSetCount-2 do *)
                             let offset2=seek_in file (offset1+6+ligset*2); offset1+readInt2 file in
                             let ligCount=seek_in file offset2; readInt2 file in
                               for lig=0 to ligCount-1 do
                                 let offset3=seek_in file (offset2+2+lig*2); offset2+readInt2 file in
                                 let ligGlyph=seek_in file offset3; readInt2 file in
                                 let compCount=readInt2 file in
                                 let arr=Array.make compCount first_glyph in
                                   for comp=1 to compCount-1 do
                                     arr.(comp)<-readInt2 file
                                   done;
                                   subst:=(Subst { original_glyphs=arr; subst_glyphs=[|ligGlyph|] })::(!subst)
                               done
                                 (* done *)
                          ) cov
            )
          | GSUB_CONTEXT->(
              let format=seek_in file offset1; readInt2 file in
                if format=1 then (
                  let coverageOff=readInt2 file in
                  let cov=readCoverageIndex file (offset1+coverageOff) in
                    List.iter (fun (first_glyph, subruleSet)->
                                 let offset2=offset1+6+subruleSet*2 in
                                 let subruleCount=seek_in file offset2; readInt2 file in
                                   for j=0 to subruleCount-1 do
                                     let subruleOff=seek_in file (offset2+2+j*2); readInt2 file in

                                     let glyphCount=seek_in file (offset2+subruleOff); readInt2 file in
                                     let substCount=readInt2 file in
                                     let arr=Array.make glyphCount (first_glyph,[]) in
                                       for i=1 to glyphCount-1 do
                                         arr.(i)<-(readInt2 file, [])
                                       done;
                                       for i=0 to substCount do
                                         let seqIdx=readInt2 file in
                                         let lookupIdx=readInt2 file in
                                           arr.(seqIdx)<-(fst arr.(i), (readLookup file gsubOff lookupIdx)@(snd arr.(i)))
                                       done;
                                       subst:=(Context arr)::(!subst)
                                   done
                              ) cov
                ) else if format=2 then (

                ) else if format=3 then (

                )
            )
          | GSUB_CHAINING->(
              let format=seek_in file offset1; readInt2 file in
                if format=1 then (

                ) else if format=2 then (

                ) else if format=3 then (
                  let backCount=readInt2 file in
                  let back_arr=Array.make backCount [] in
                    for i=1 to backCount do
                      let covOff=seek_in file (offset1+2+i*2); readInt2 file in
                      let cov=readCoverageIndex file (offset1+covOff) in
                        List.iter (fun (a,_)->back_arr.(backCount-i)<-a::back_arr.(backCount-i)) cov
                    done;
                    let offset2=offset1+4+backCount*2 in
                    let inputCount=seek_in file offset2; readInt2 file in
                    let input_arr=Array.make inputCount [] in
                      for i=0 to inputCount-1 do
                        let covOff=seek_in file (offset2+2+i*2); readInt2 file in
                        let cov=readCoverageIndex file (offset1+covOff) in
                          List.iter (fun (a,_)->input_arr.(i)<-a::input_arr.(i)) cov
                      done;
                      let offset3=offset2+2+inputCount*2 in
                      let aheadCount=seek_in file offset3; readInt2 file in
                      let ahead_arr=Array.make aheadCount [] in
                        for i=0 to aheadCount-1 do
                          let covOff=seek_in file (offset3+2+i*2); readInt2 file in
                          let cov=readCoverageIndex file (offset1+covOff) in
                            List.iter (fun (a,_)->ahead_arr.(i)<-a::ahead_arr.(i)) cov
                        done;
                        subst:=(Chain {before=back_arr; input=input_arr; after=ahead_arr})::(!subst)
                );
            )
          | _->()
    done;
    List.rev !subst


let read_gsub font=
  let (file_,off0)=otype_file font in
  let file=open_in_bin_cached file_ in
  let (gsubOff,_)=tableLookup "GSUB" file off0 in
  let lookup= seek_in file (gsubOff+8); readInt2 file in
  let lookupCount= seek_in file (gsubOff+lookup); readInt2 file in
    (* Iteration sur les lookuptables *)
  let arr=Array.make lookupCount [] in
    for i=0 to lookupCount-1 do
      arr.(i)<-readLookup file gsubOff i
    done;
    arr

let read_lookup font i=
  let (file_,off0)=otype_file font in
  let file=open_in_bin_cached file_ in
  let (gsubOff,_)=tableLookup "GSUB" file off0 in
  let x=readLookup file gsubOff i in
    x


let alternates = "aalt"
let smallCapitals = "c2sc"
let caseSensitiveForms = "case"
let discretionaryLigatures = "dlig"
let denominators = "dnom"
let fractions = "frac"
let standardLigatures = "liga"
let liningFigures = "lnum"
let localizedForms = "locl"
let numerators = "numr"
let oldStyleFigures = "onum"
let ordinals = "odrn"
let ornaments = "ornm"
let proportionalFigures = "pnum"
let stylisticAlternates = "salt"
let scientificInferiors = "sinf"
let subscript = "subs"
let superscript = "sups"
let titling = "titl"
let tabularFigures = "tnum"
let slashedZero = "zero"

let select_features font feature_tags=try
  let (file_,off0)=otype_file font in
  let file=open_in_bin_cached file_ in
  let (gsubOff,_)=tableLookup "GSUB" file off0 in
  let features=seek_in file (gsubOff+6); readInt2 file in
  let featureCount=seek_in file (gsubOff+features);readInt2 file in
  let feature_tag=String.create 4 in
  let rec select i result=
    if i>=featureCount then result else (
        seek_in file (gsubOff+features+2+i*6);
        let _=input file feature_tag 0 4 in
        let lookupOff=readInt2 file in
        let lookupCount=seek_in file (gsubOff+features+lookupOff+2); readInt2 file in
        let rec read lookup s=
          if lookup>=lookupCount then s else (
            let l=readInt2 file in read (lookup+1) (l::s)
          )
        in
          if List.mem feature_tag feature_tags then
            select (i+1) (read 0 result)
          else
            select (i+1) result
    )
  in
  let x=List.concat (List.map (fun lookup->readLookup file gsubOff lookup) (select 0 [])) in
    x

with Table_not_found _->[]

let font_features font=try
  let (file_,off0)=otype_file font in
  let file=open_in_bin_cached file_ in
  let (gsubOff,_)=tableLookup "GSUB" file off0 in

  let features=seek_in file (gsubOff+6); readInt2 file in
  let featureCount=seek_in file (gsubOff+features);readInt2 file in
  let buf=String.create 4 in
  let rec make_features i result=
    if i>=featureCount then result else (
      seek_in file (gsubOff+features+2+i*6);
      let _=input file buf 0 4 in
        make_features (i+1) (String.copy buf::result)
    )
  in
  make_features 0 []

with Table_not_found _->[]


let read_scripts font=
  let (file,off0)=otype_file font in
  let file=open_in_bin_cached file in
  let (gsubOff,_)=tableLookup "GSUB" file off0 in
  let scripts=seek_in file (gsubOff+4); readInt2 file in
  let scriptCount=seek_in file (gsubOff+scripts); readInt2 file in
    for i=0 to scriptCount-1 do
      let scriptTag=String.create 4 in
        seek_in file (gsubOff+scripts+2+i*6);
        let _=input file scriptTag 0 4 in
        let off=readInt2 file in
          Printf.printf "\n%s\n" scriptTag;
          let offset1=gsubOff+scripts+off in
          let langSysCount=seek_in file (offset1+2); readInt2 file in
            for langSys=0 to langSysCount-1 do
              let langSysTag=String.create 4 in
                seek_in file (offset1+4+langSys*6);
                let _=input file langSysTag 0 4 in
                  Printf.printf "lang : %s\n" langSysTag
          done
    done


#define GPOS_SINGLE 1
#define GPOS_PAIR 2

let rec gpos font glyphs0=
  let (file,off0)=otype_file font in
  let file=open_in_bin_cached file in
  let (gposOff,_)=tableLookup "GPOS" file off0 in
  let lookup= seek_in file (gposOff+8); readInt2 file in
  let lookupCount= seek_in file (gposOff+lookup); readInt2 file in
  let glyphs=ref glyphs0 (* (List.map (fun x->GlyphID x) glyphs0) *) in
    (* Iteration sur les lookuptables *)
    for i=1 to lookupCount do
      let offset=seek_in file (gposOff+lookup+i*2); readInt2 file in

      let lookupType=seek_in file (gposOff+lookup+offset); readInt2 file in
      (* let lookupFlag=seek_in file (gposOff+lookup+offset+2); readInt2 file in *)
      let subtableCount=seek_in file (gposOff+lookup+offset+4); readInt2 file in
      let maxOff=gposOff+lookup+offset + 6+subtableCount*2 in

      let rec lookupSubtables off gl=
        if off>=maxOff then gl else
          let subtableOff=seek_in file off; readInt2 file in
          let offset=gposOff+lookup+offset+subtableOff in


          let rec gpos glyphs=
            (* Printf.printf "lookupType=%d\n" lookupType; *)
            match glyphs with

                id_h::id_h'::s->(
                  let h=glyph_id_cont id_h in
                  let h'=glyph_id_cont id_h' in
                  match lookupType with
                      GPOS_PAIR->(
                        let format=seek_in file offset; readInt2 file in
                          (* Printf.printf "format : %d\n" format; *)
                        let coverageOffset=readInt2 file in
                        let valueFormat1=readInt2 file in
                        let valueFormat2=readInt2 file in

                        let rec compute_size x r=if x=0 then r else compute_size (x lsr 1) (r+(x land 1)) in
                        let size1=compute_size valueFormat1 0 in
                        let size2=compute_size valueFormat2 0 in
                        let readAll format gl=
                          { kern_x0=if (format land 0x1) <> 0 then float_of_int (int16 (readInt2 file)) else 0.;
                            kern_y0=if (format land 0x2) <> 0 then float_of_int (int16 (readInt2 file)) else 0.;
                            advance_width=if (format land 0x4) <> 0 then float_of_int (int16 (readInt2 file)) else 0.;
                            advance_height=if (format land 0x8) <> 0 then float_of_int (int16 (readInt2 file)) else 0.;
                            kern_contents=gl }
                        in
                          try
                            let coverage=coverageIndex file (offset+coverageOffset) h in
                              if format=1 then (
                                let rec pairSetTable off0 x0 x1=
                                  let x2=(x0+x1)/2 in
                                  let gl=seek_in file (off0+x2*(1+size1+size2)*2); readInt2 file in
                                    if x1-x0<=1 then
                                      if gl=h' then readAll valueFormat1 id_h, readAll valueFormat2 id_h' else raise Not_found
                                    else
                                      if gl>h' then pairSetTable off0 x0 x2 else pairSetTable off0 x2 x1
                                in
                                let pairSetOffset=seek_in file (offset+10+coverage*2); readInt2 file in
                                let count=seek_in file (offset+pairSetOffset); readInt2 file in
                                let a,b=pairSetTable (offset+pairSetOffset+2) 0 count in
                                  (if valueFormat1<>0 then KernID a else id_h)::
                                    (gpos ((if valueFormat2<>0 then KernID b else id_h')::s))
                              ) else if format=2 then (

                                let classdef1=seek_in file (offset+8); class_def file (offset+readInt2 file) h in
                                let classdef2=seek_in file (offset+10); class_def file (offset+readInt2 file) h' in
                                let class1count=seek_in file (offset+12); readInt2 file in
                                let class2count=seek_in file (offset+14); readInt2 file in
                                  if classdef1>class1count || classdef2>class2count then
                                    glyphs
                                  else
                                    (let index=16
                                       + (class2count*2*(size1+size2))*classdef1
                                       + 2*(size1+size2)*h'
                                     in
                                       seek_in file (offset+index);
                                       let a=readAll valueFormat1 id_h in
                                       let b=readAll valueFormat2 id_h' in
                                         (if valueFormat1<>0 then KernID a else id_h)::
                                           (gpos ((if valueFormat2<>0 then KernID b else id_h')::s))
                                    )
                              ) else glyphs
                          with
                              Not_found->glyphs
                      )
                    | _->glyphs
                )
              | [h]->[h]
              | [] -> []
          in
            lookupSubtables (off+2) (gpos gl)
      in
        glyphs:=lookupSubtables (gposOff+lookup+offset + 6) !glyphs
    done;
    !glyphs


let positioning font glyphs0=try gpos font glyphs0 with Table_not_found _->glyphs0


(****************************************************************)

type fontInfo=
    { mutable tables:string StrMap.t;
      mutable fontType:string }

let fontInfo font=
  let file,off=match font with
      CFF (cff,off)->cff.file,off
  in
  let file=open_in_bin_cached file in
  let fontType=String.create 4 in
  seek_in file off;
  really_input file fontType 0 4;
  seek_in file (off+4);
  let numTables=readInt2 file in
  let rec getTables n l=
    if n<offsetTable then l else (
      seek_in file (off+n);
      let newTable=String.create 4 in
      really_input file newTable 0 4;
      let _ (* checkSum *)=readInt4 file in
      let offset=readInt4 file in
      let length=readInt4 file in
      seek_in file (off+offset);
      let buf=String.create length in
      really_input file buf 0 length;
      Printf.fprintf stderr "Opentype.fontInfo:%S\n" newTable;
      getTables (n-dirSize) (StrMap.add newTable buf l)
    )
  in
  { tables=getTables (off+dirSize*(numTables-1)+offsetTable) StrMap.empty;
    fontType=fontType }




let rec checksum32 x=
  let cs=ref 0 in
  for i=0 to Rbuffer.length x-1 do
    cs:= (!cs+int_of_char (Rbuffer.nth x i)) land 0xffffffff
  done;
  !cs

let rec str_checksum32 x=
  let cs=ref 0 in
  let i=ref 0 in
  while !i<String.length x do
    let a=int_of_char x.[!i] in
    let b=if !i+1<String.length x then int_of_char (x.[!i+1]) else 0 in
    let c=if !i+2<String.length x then int_of_char (x.[!i+2]) else 0 in
    let d=if !i+3<String.length x then int_of_char (x.[!i+3]) else 0 in
    cs:= (!cs+((((((a lsl 8) lor b) lsl 8) lor c) lsl 8) lor d)) land 0xffffffff;
    i:= !i+4
  done;
  !cs

let rec buf_checksum32 x=
  let cs=ref 0 in
  let i=ref 0 in
  while !i<Rbuffer.length x do
    let a=int_of_char (Rbuffer.nth x !i) in
    let b=if !i+1<Rbuffer.length x then int_of_char (Rbuffer.nth x (!i+1)) else 0 in
    let c=if !i+2<Rbuffer.length x then int_of_char (Rbuffer.nth x (!i+2)) else 0 in
    let d=if !i+3<Rbuffer.length x then int_of_char (Rbuffer.nth x (!i+3)) else 0 in
    cs:= (!cs+((((((a lsl 8) lor b) lsl 8) lor c) lsl 8) lor d)) land 0xffffffff;
    i:= !i+4
  done;
  !cs

let write_cff fontInfo=

  let buf=Rbuffer.create 256 in
  Rbuffer.add_string buf fontInfo.fontType;
  bufInt2 buf (StrMap.cardinal fontInfo.tables);
  let rec searchRange a b k=if a=1 then b lsl 4,k else searchRange (a lsr 1) (b lsl 1) (k+1) in
  let sr,log2=searchRange (StrMap.cardinal fontInfo.tables) 1 0 in
  Printf.printf "opentype : sr=%d, log2=%d\n" sr log2;
  bufInt2 buf sr;
  bufInt2 buf log2;
  bufInt2 buf ((StrMap.cardinal fontInfo.tables lsl 4) - sr);
  let buf_tables=Rbuffer.create 256 in
  let buf_headers=Rbuffer.create 256 in
  let write_tables checksums=
    StrMap.fold (fun k a _->
      Printf.fprintf stderr "writing table %S\n" k;
      while (Rbuffer.length buf_tables) land 3 <> 0 do
        Rbuffer.add_char buf_tables (char_of_int 0)
      done;
      Rbuffer.add_string buf_headers k;
      let cs=StrMap.find k checksums in
      bufInt4 buf_headers cs;
      bufInt4 buf_headers (12+16*StrMap.cardinal fontInfo.tables+Rbuffer.length buf_tables);
      bufInt4 buf_headers (String.length a);
      Rbuffer.add_string buf_tables a
    ) fontInfo.tables ()
  in
  (try
     let buf_head=StrMap.find "head" fontInfo.tables in
     strInt4 buf_head 8 0;
     let checksums=StrMap.map (fun a->str_checksum32 a) fontInfo.tables in
     write_tables checksums;
     let total_checksum=
       (buf_checksum32 buf
        +buf_checksum32 buf_headers
        +buf_checksum32 buf_tables) land 0xffffffff
     in
     Rbuffer.clear buf_tables;
     Rbuffer.clear buf_headers;
     let check=Int32.sub (Int32.of_int (-1313820742)) (Int32.of_int total_checksum) in
     strInt4 buf_head 8 (Int32.to_int check);
     Printf.fprintf stderr "%x %x %x %x\n"
       (int_of_char buf_head.[8])
       (int_of_char buf_head.[9])
       (int_of_char buf_head.[10])
       (int_of_char buf_head.[11]);
     Printf.fprintf stderr "total checksum=%x %x\n" (total_checksum) (Int32.to_int check);
     write_tables checksums
   with
       Not_found->failwith "no head table"
  );
  Rbuffer.add_buffer buf buf_headers;
  Rbuffer.add_buffer buf buf_tables;
  while (Rbuffer.length buf) land 3 <> 0 do
    Rbuffer.add_char buf (char_of_int 0)
  done;
  buf


let make_tables font fontInfo glyphs=
  let fontInfo_tables=fontInfo.tables in
  fontInfo.tables<-StrMap.remove "kern" fontInfo.tables;
  (* cmap *)
  Printf.fprintf stderr "cmap\n"; flush stderr;
  let r_cmap=ref IntMap.empty in
  (try
     let tmp0=Filename.temp_file "cmap_" "" in
     let o=open_out tmp0 in
     output_string o (StrMap.find "cmap" fontInfo_tables);
     close_out o;
     let file=open_in tmp0 in
     let old_cmap=Cmap.read_cmap file 0 in
     close_in file;

     let buf=Rbuffer.create 256 in
     let charset=ref IntMap.empty in
     for i=0 to Array.length glyphs-1 do
       charset:=IntMap.add
         ((glyphNumber glyphs.(i)).glyph_index)
         i
         !charset
     done;
     r_cmap:=
       IntMap.fold (fun k a m->
         try
           IntMap.add k (IntMap.find a !charset) m
         with
             Not_found->m
       ) old_cmap IntMap.empty;
     Cmap.write_cmap ~formats:[4] !r_cmap buf;
     fontInfo.tables<-StrMap.add "cmap" (Rbuffer.contents buf) fontInfo.tables
   with
       Not_found->());
  let cmap= !r_cmap in

  Printf.fprintf stderr "hmtx\n"; flush stderr;
  (* hmtx *)
  let numberOfHMetrics=ref (Array.length glyphs-1) in
  let buf_hmtx=String.create (2*(Array.length glyphs)+2*(!numberOfHMetrics+1)) in
  let advanceWidthMax=ref 0 in
  while !numberOfHMetrics>0 &&
    glyphWidth glyphs.(!numberOfHMetrics) = glyphWidth glyphs.(!numberOfHMetrics-1) do
    decr numberOfHMetrics
  done;
  for i=0 to !numberOfHMetrics do
    let w=glyphWidth glyphs.(i) in
    let x0=round (glyph_x0 glyphs.(i)) in
    advanceWidthMax:=max !advanceWidthMax (round w);
    strInt2 buf_hmtx (i*4) (round w);
    strInt2 buf_hmtx (i*4+2) x0
  done;
  for i= !numberOfHMetrics+1 to Array.length glyphs-1 do
    let x0=round (glyph_x0 glyphs.(i)) in
    strInt2 buf_hmtx (4*(!numberOfHMetrics+1)+2*i) x0
  done;

  fontInfo.tables<-StrMap.add "hmtx" buf_hmtx fontInfo.tables;


  Printf.fprintf stderr "hhea\n"; flush stderr;
  (* hhea *)
  let xAvgCharWidth=ref 0. in
  let yMax=ref (-.infinity) in
  let yMin=ref infinity in
  let xMax=ref (-.infinity) in
  let xMin=ref infinity in
  (try
     let ascender=ref 0 in
     let descender=ref 0 in
     let minLSB=ref infinity in
     let minRSB=ref infinity in
     for i=0 to Array.length glyphs-1 do
       ascender:=max !ascender (round (glyph_y1 glyphs.(i)));
       descender:=min !descender (round (glyph_y0 glyphs.(i)));

       let lsb=glyph_x0 glyphs.(i) in
       let x1=glyph_x1 glyphs.(i) in
       minLSB:=min !minLSB lsb;
       let aw=glyphWidth glyphs.(i) in
       minRSB:=min !minRSB (aw -. x1);
       xMax:=max !xMax x1;
       xMin:=min !xMin lsb;
       yMax:=max !yMax (glyph_y1 glyphs.(i));
       yMin:=min !yMin (glyph_y0 glyphs.(i));
       xAvgCharWidth:= !xAvgCharWidth+.aw
     done;

     let buf_hhea=StrMap.find "hhea" fontInfo_tables in
     strInt4 buf_hhea 0 0x00010000;        (* Version *)
     (* strInt2 buf_hhea 4 (!ascender); (\* Ascender *\) *)
     (* strInt2 buf_hhea 6 (!descender);        (\* Descender *\) *)
     (* strInt2 buf_hhea 8 0; *)           (* LineGap *)
     strInt2 buf_hhea 10 !advanceWidthMax;  (* advanceWidthMax (hmtx) *)
     strInt2 buf_hhea 12 (round !minLSB);           (* minLeftSideBearing *)
     strInt2 buf_hhea 14 (round !minRSB);           (* minRightSideBearing *)
     strInt2 buf_hhea 16 (round (!minLSB+. !xMax-. !xMin)); (* xMaxExtent *)
     strInt2 buf_hhea 34 (!numberOfHMetrics+1) (* numberOfHMetrics (hmtx) *)
   with
       Not_found -> ());

  Printf.fprintf stderr "head\n"; flush stderr;
  (* head *)
  (try
     let buf_head=StrMap.find "head" fontInfo_tables in
     strInt2 buf_head 32 (round !xMin);
     strInt2 buf_head 34 (round !yMin);
     strInt2 buf_head 36 (round !xMax);
     strInt2 buf_head 38 (round !yMax)
   with
       Not_found->());

  Printf.fprintf stderr "maxp\n"; flush stderr;
  (* maxp *)
  (if fontInfo.fontType="OTTO" then (
    let buf_maxp=String.create 6 in
    buf_maxp.[0]<-char_of_int 0x00;
    buf_maxp.[1]<-char_of_int 0x00;
    buf_maxp.[2]<-char_of_int 0x50;
    buf_maxp.[3]<-char_of_int 0x00;
    strInt2 buf_maxp 4 (Array.length glyphs);
    fontInfo.tables<-StrMap.add "maxp" buf_maxp fontInfo.tables
   ));



  Printf.fprintf stderr "os/2\n"; flush stderr;
  (* os/2 *)
  (try
     let buf_os2=StrMap.find "OS/2" fontInfo_tables in
     strInt2 buf_os2 2 ((round (!xAvgCharWidth/.float_of_int (Array.length glyphs))));
     let u1=ref 0 in
     let u2=ref 0 in
     let u3=ref 0 in
     let u4=ref 0 in
     let _=IntMap.fold (fun k _ _->Unicode_ranges.unicode_range u1 u2 u3 u4 k) cmap () in
     strInt4 buf_os2 42 !u1;
     strInt4 buf_os2 46 !u2;
     strInt4 buf_os2 50 !u3;
     strInt4 buf_os2 54 !u4;

     Printf.printf "usFirst/Last : %d/%d\n" (fst (IntMap.min_binding cmap)) (fst (IntMap.max_binding cmap));
     strInt2 buf_os2 74 0x10; (* (fst (IntMap.min_binding cmap)); *) (* usFirstCharIndex *)
     strInt2 buf_os2 76 (fst (IntMap.max_binding cmap)); (* usLastCharIndex *)
     Printf.fprintf stderr "usBreakChar : %d\n" (fst (IntMap.min_binding cmap));
     strInt2 buf_os2 92 (if IntMap.mem 0x20 cmap then 0x20 else (fst (IntMap.min_binding cmap))); (* usBreakChar *)

     (* strInt2 buf_os2 64 (round !yMax);              (\* usWinAscent *\) *)
     (* strInt2 buf_os2 66 (max 0 (round (-. !yMin))); (\* usWinDescent *\) *)

     (* (try *)
     (*    let ix=IntMap.find 0x78 cmap in *)
     (*    if ix>0 && ix<Array.length glyphs then *)
     (*      let sxHeight=glyph_y1 glyphs.(ix) in *)
     (*      strInt2 buf_os2 86 (round sxHeight) *)
     (*  with *)
     (*      _->()); *)
     (* (try *)
     (*    let iH=IntMap.find 0x48 cmap in *)
     (*    if iH>0 && iH<Array.length glyphs then *)
     (*      let capHeight=glyph_y1 glyphs.(iH) in *)
     (*      strInt2 buf_os2 88 (round capHeight) *)
     (*  with *)
     (*      _->()); *)
   with
       Not_found->()
  );

  Printf.fprintf stderr "CFF \n"; flush stderr;
  (* CFF  *)
  (match font with
      CFF (cff,_)->(
        let glyphs_arr=Array.map (fun g->(glyphNumber g).glyph_index) glyphs in
        let cff'=(CFF.subset cff glyphs_arr) in
        (try
           let o=open_out "original.cff" in
           output_string o (StrMap.find "CFF " fontInfo_tables);
           close_out o;
         with Not_found -> Printf.fprintf stderr "dommage\n";);
        let o=open_out "subset.cff" in
        Rbuffer.output_buffer o cff';
        close_out o;
        fontInfo.tables<-StrMap.add "CFF " (Rbuffer.contents cff') fontInfo.tables
      ))


let subset font glyphs=
  let info=fontInfo font in
  make_tables font info glyphs;
  write_cff info
