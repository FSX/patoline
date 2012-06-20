open Typography

type 'a spec=
    Alpha of 'a
  | Font of 'a
  | Case of 'a
  | Graisse of 'a
  | Width of int

let styles=List.map (fun (a,b)->a,(List.sort compare b))
  [[36,61],[Alpha `Latin;Case `Maj];
   [68,93],[Alpha `Latin;Case `Min];
   [1092,1117],[Alpha `Latin;Case `Maj;Width 1];
   [1118,1143],[Alpha `Latin;Case `Min;Width 1];
   [1522,1547],[Alpha `Latin;Case `Maj;Width 2];
   [1548,1573],[Alpha `Latin;Case `Min;Width 2];

   [422,447],[Alpha `Latin;Case `Maj;Graisse `Gras];
   [448,473],[Alpha `Latin;Case `Min;Graisse `Gras];
   [987,1012],[Alpha `Latin;Case `Maj;Graisse `Gras;Width 1];
   [1014,1039],[Alpha `Latin;Case `Min;Graisse `Gras;Width 1];
   [1417,1442],[Alpha `Latin;Case `Maj;Graisse `Gras;Width 2];
   [1444,1469],[Alpha `Latin;Case `Min;Graisse `Gras;Width 2];

   [1150,1175],[Alpha `Latin;Case `Maj;Font `Cal;Graisse `Gras];
   [1183,1208],[Alpha `Latin;Case `Maj;Font `Cal];
   [1580,1604],[Alpha `Latin;Case `Maj;Font `Cal;Width 1;Graisse `Gras];
   [1613,1628],[Alpha `Latin;Case `Maj;Font `Cal;Width 1];
   [518,519;
    886,886;
    520,523;
    891,892;
    524,531;
    901,901;
    532,538;
    909,909],[Alpha `Latin;Case `Maj;Font `Fraktur];
   [539,564],[Alpha `Latin;Case `Min;Font `Fraktur];
   [884,909],[Alpha `Latin;Case `Maj;Font `Fraktur;Width 1];
   [910,935],[Alpha `Latin;Case `Min;Font `Fraktur;Width 1];
   [1314,1339],[Alpha `Latin;Case `Maj;Font `Fraktur;Width 2];
   [1340,1365],[Alpha `Latin;Case `Min;Font `Fraktur;Width 2];

   [565,591],[Alpha `Latin;Case `Maj;Graisse `Gras;Font `Fraktur];
   [592,616],[Alpha `Latin;Case `Min;Graisse `Gras;Font `Fraktur];
   [709,736],[Alpha `Latin;Case `Maj;Graisse `Gras;Font `Fraktur;Width 1];
   [740,765],[Alpha `Latin;Case `Min;Graisse `Gras;Font `Fraktur;Width 1];
   [1239,1264],[Alpha `Latin;Case `Maj;Graisse `Gras;Font `Fraktur;Width 2];
   [1268,1293],[Alpha `Latin;Case `Min;Graisse `Gras;Font `Fraktur;Width 2];

   [19,28],[Alpha `Chiffres];
   [1081,1090],[Alpha `Chiffres;Width 1];
   [1511,1520],[Alpha `Chiffres;Width 2];
   [1404,1413],[Alpha `Chiffres;Graisse `Gras]
  ]

let get_index c l=
  let rec get_index x0=function
      []->None
    | (a,b)::_ when c>=a && c<=b -> Some (x0+c-a)
    | (a,b)::s->get_index (x0+b-a+1) s
  in
    get_index 0 l

let rec categorize c=function
    []->None
  | (a,b)::s->(
      match get_index c a with
          None->categorize c s
        | Some x->Some (x,b)
    )

let subst_index c l=
  let rec subst_index x0=function
      []->None
    | (a,b)::_ when x0<=b-a -> Some (a+x0)
    | (a,b)::s->subst_index (x0-(b-a+1)) s
  in
    subst_index c l

let _=categorize 44 styles
let make_subst l c=
  match categorize c styles with
      None->c
    | Some (a,b)->(
        let filtered=List.fold_left
          (fun u v->
             List.filter (fun x->match v,x with
                              Font _,Font _->false
                            | Alpha _,Alpha _->false
                            | Case _,Case _->false
                            | Width _,Width _->false
                            | Graisse _,Graisse _->false
                            | _->true
                         ) u
          ) b l
        in
        let carac=List.sort compare (filtered@l) in
          try (
            match subst_index a (fst (List.find (fun (_,x)->x=carac) styles)) with
                None->c
              | Some u->u
          ) with
              Not_found -> c
      )
open Fonts.FTypes
let subst l cs=List.map (fun c->{ c with glyph_index=make_subst l c.glyph_index }) cs
open Document
open Document.Mathematical
open Maths
open Util


let compose f g x=f(g x)
let changeFont l env=
  { env with mathsEnvironment=
      Array.map (fun x->{ x with mathsSubst=compose (subst l) x.mathsSubst })
        env.mathsEnvironment }
let default_env=
    {
      mathsFont=Lazy.lazy_from_fun (fun () -> Fonts.loadFont (findFont "Euler/euler.otf"));
      mathsSubst=(fun x->(* List.iter (fun x->Printf.printf "normal : %d\n" x.glyph_index) x; *) x);
      mathsSize=1.;
      numerator_spacing=0.18;
      denominator_spacing=0.14;
      sub1= 0.2;
      sub2= 0.2;
      sup1=0.5;
      sup2=0.5;
      sup3=0.5;
      sub_drop=0.2;
      sup_drop=0.2;
      default_rule_thickness=0.05;
      subscript_distance= 0.15;
      superscript_distance= 0.15;
      limit_subscript_distance= 0.15;
      limit_superscript_distance= 0.15;
      invisible_binary_factor = 0.75;
      open_dist=0.15;
      close_dist=0.15;
      kerning=true;
      priorities=[| 4.;3.;2.;1. |];
      priority_unit=1./.9.
    }
let msubst m x=List.map (fun x->try
                           { x with glyph_index=IntMap.find x.glyph_index m }
                         with
                             Not_found->x) x

let displaySubst=Lazy.lazy_from_fun
  (fun ()->
     List.fold_left (fun m (a,b)->IntMap.add a b m) IntMap.empty
       [(* Sum operators *)
         778,779;
         275,779])

let default=[|
  { default_env with mathsSubst=msubst (Lazy.force displaySubst) };
  { default_env with mathsSubst=msubst (Lazy.force displaySubst) };
  default_env;
  default_env;
  { default_env with mathsSize=2./.3. };
  { default_env with mathsSize=2./.3. };
  { default_env with mathsSize=4./.9. };
  { default_env with mathsSize=4./.9. }
|]
