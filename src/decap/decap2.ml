open Charset
open Input
open Str

let debug_lvl = ref 0

exception Give_up of string

let give_up s = raise (Give_up s)

type blank = buffer -> int -> buffer * int

let no_blank str pos = str, pos

let blank_regexp r =
  let r = Str.regexp r in
  let accept_newline = string_match r "\n" 0 && match_end () = 1 in
  let rec fn str pos =
    let str,pos = normalize str pos in
    if string_match r (line str) pos then
      let pos' = match_end () in
      if accept_newline && pos' = String.length (line str) && not (is_empty str pos') then fn str pos'
      else str, pos'
    else str, pos
  in
  fn

(** A BNF grammar is a list of rules. The type parameter ['a] corresponds to
    the type of the semantics of the grammar. For example, parsing using a
    grammar of type [int grammar] will produce a value of type [int]. *)
type 'a grammar = 'a rule list

and 'a symbol =
  | Term of (buffer -> int -> 'a * buffer * int)
  (** terminal symbol just read the input buffer *)
  | NonTerm of 'a grammar
  (** non terminal *)
  | RefTerm of 'a grammar ref
  (** non terminal trough a reference to define recursive grammars *)

(** BNF rule. *)
and _ rule =
  | Empty : 'a -> 'a rule
  (** Empty rule. *)
  | EmptyPos : (buffer -> int -> buffer -> int -> 'a) -> 'a rule
  (** Empty rule. recoreding positions *)
  | Dep : ('b -> 'a rule) -> ('b -> 'a) rule
  (** Dependant rule *)
  | Next : 'b symbol * ('b -> 'a) rule -> 'a rule
  (** Sequence of a symbol and a rule. *)
  | IgnNext : 'b symbol * ('b -> 'a) rule -> 'a rule
  (** Sequence of a symbol and a rule, with no blank after the symbol. *)

type (_) actions =
  | Nothing : ('a -> 'a) actions
  | Something : 'a Lazy.t * ('b -> 'c) actions -> (('a -> 'b) -> 'c) actions

type (_) shifts =
  | Unit   : unit shifts
  | Direct : ('a -> 'a) shifts
  | Shift  : ('a -> 'b) * ('b -> 'c) actions * ('c -> 'd) shifts -> ('a -> 'd) shifts
  | ShiftPos  : (buffer -> int -> buffer -> int -> 'a -> 'b)
      * ('b -> 'c) actions * ('c -> 'd) shifts -> ('a -> 'd) shifts

let rec apply_actions : type a b.(a -> b) actions -> a -> b =
  fun l a ->
    match l with
    | Nothing -> a
    | Something(lazy b,l') -> apply_actions l' (a b)

let rec apply_shifts : type a b.(buffer*int) -> (buffer*int) -> (a -> b) shifts -> a -> b =
  fun (buf, pos as debut) (buf',pos' as fin) l a ->
    match l with
    | Direct -> a
    | Shift(f,acts,s) -> apply_shifts debut fin s (apply_actions acts (f a))
    | ShiftPos(f,acts,s) ->
       let f = f buf pos buf' pos' in
       apply_shifts debut fin s (apply_actions acts (f a))

(* type de la table de Earley *)
type position = buffer * int
type ('s,'a,'b,'c,'d,'r) cell = {
  ignb:bool; (*ignb!ignore next blank*)
  debut : position;
  debut_after_blank : position;
  fin   : position;
  stack : ('d, 'r) element list ref;
  acts  : 'a actions;
  shifts: 's shifts;
  rest  : 'b rule;
  full  : 'c rule }
and (_,_) element = C : ('a -> 's, 'b -> 'c, 's -> 'b, 'c, 'c, 'r) cell -> ('a,'r) element
and _ final   = D : (unit, 'b -> 'c, 'b, 'c, 'c, 'r) cell -> 'r final
(* si t : table et t.(j) = (i, R, R' R) cela veut dire qu'entre i et j on a parsé
   la règle R' et qu'il reste R à parser. On a donc toujours
   i <= j et R suffix de R' R (c'est pour ça que j'ai écris R' R)
*)

type ('a,'b) eq  = Eq : ('a, 'a) eq | Neq : ('a, 'b) eq

let (===) : type a b.a -> b -> (a,b) eq = fun r1 r2 ->
  if Obj.repr r1 == Obj.repr r2 then Obj.magic Eq else Neq

let eq : 'a 'b.'a -> 'b -> bool = fun x y -> (x === y) <> Neq

let idtEmpty = Empty(fun x -> x)

let iter_rules : type a.(a rule -> unit) -> a grammar -> unit = List.iter

type _ dep_pair = P : 'a rule * ('a, 'b) element list ref * (('a, 'b) element -> unit) ref -> 'b dep_pair

let memo_assq : type a b. a rule -> b dep_pair list ref -> ((a, b) element -> unit) -> unit =
  fun r l0 f ->
    let rec fn = function
      | [] -> l0 := P(r,ref [], ref f)::!l0
      | P(r',ptr,g)::l ->
	 match r === r' with
	 | Eq -> g := let g = !g in (fun el -> f el; g el)
	 | _ -> fn l
    in fn !l0

let add_assq : type a b. a rule -> (a, b) element -> b dep_pair list ref -> (a, b) element list ref =
  fun r el l0 ->
    let rec fn = function
      | [] -> let res = ref [el] in l0 := P(r,res, ref (fun el -> ()))::!l0; res
      | P(r',ptr,g)::l ->
	 match r === r' with
	 | Eq -> ptr := el :: !ptr; !g el; ptr
	 | _ -> fn l
    in fn !l0

let solo = fun s -> [Next(Term s,idtEmpty)]

let next : type a b.a grammar -> (a -> b) rule -> b rule =
  fun s r -> match s with
  | [Next(s0,e)] ->
      (match e === idtEmpty with Eq -> Next(s0,r) | Neq -> Next(NonTerm s,r))
  | [IgnNext(s0,e)] ->
      (match e === idtEmpty with Eq -> IgnNext(s0,r) | Neq -> Next(NonTerm s,r))
  | s -> Next(NonTerm s,r)

let ignNext : type a b.a grammar -> (a -> b) rule -> b rule =
  fun s r -> match s with
  | [Next(s0,e)] ->
      (match e === idtEmpty with Eq -> IgnNext(s0,r) | Neq -> IgnNext(NonTerm s,r))
  | [IgnNext(s0,e)] ->
      (match e === idtEmpty with Eq -> IgnNext(s0,r) | Neq -> IgnNext(NonTerm s,r))
  | s -> Next(NonTerm s,r)


let debut = function D { debut } -> debut
let fin   = function D { fin   } -> fin
let is_term = function D { rest= Next(Term _, _) } -> true | _ -> false

type 'a pos_tbl = (int * int * string, 'a final list) Hashtbl.t

let find_pos_tbl t (buf,pos) = Hashtbl.find t (line_beginning buf, pos, fname buf)
let add_pos_tbl t (buf,pos) v = Hashtbl.replace t (line_beginning buf, pos, fname buf) v
let char_pos (buf,pos) = line_beginning buf + pos
let eq_pos (buf,pos) (buf',pos') = eq_buf buf buf' && pos = pos'

let eq_D (D {debut; fin; rest; full; ignb}) (D {debut=d'; fin=f'; rest=r'; full=fu'; ignb=ignb'}) =
  eq_pos debut d' && eq rest r' && eq full fu' && ignb=ignb'

(* ajoute un élément dans la table et retourne true si il est nouveau *)
let add : string -> 'a final -> 'a pos_tbl -> bool =
  fun info element old ->
    let debut = debut element in
    let oldl = try find_pos_tbl old debut with Not_found -> [] in
    let absent = not (List.exists (eq_D element) oldl) in
    if absent then begin
      if !debug_lvl > 1 then Printf.eprintf "add %s %d %d %b\n%!" info (char_pos debut)
	(char_pos (fin element)) (is_term element) ;
      add_pos_tbl old debut (element :: oldl);
    end;
    absent

let taille : 'a final -> int = fun el ->
  let cast_elements : type a b.(a,b) element list -> (Obj.t, Obj.t) element list = Obj.magic in
  let adone = ref [] in
  let res = ref 1 in
  let rec fn : (Obj.t, Obj.t) element list -> unit =
    fun els ->
      if List.exists (eq els) !adone then () else begin
	res := !res + List.length els;
	adone := els :: !adone;
	List.iter (function C {stack} -> fn (cast_elements !stack)) els
      end
  in
  match el with D {stack} -> fn (cast_elements !stack); !res

type string_tree =
    TEmpty | Message of string | Expected of string | Node of string_tree * string_tree

exception Error of string_tree

let expected s = raise (Error (Expected s))
let unexpected s = raise (Error (Message s))

let (@@) t1 t2 = Node(t1,t2)
let (~~) t1 = Expected t1
let (~!) t1 = Message t1

let collect_tree t =
  let adone = ref [] in
  let rec fn acc acc' t =
    if List.memq t !adone then acc, acc' else begin
      adone := t :: !adone;
      match t with
	TEmpty -> acc, acc'
      | Message t -> if List.mem t acc then acc, acc' else (t::acc), acc'
      | Expected t -> if List.mem t acc' then acc, acc' else acc, (t::acc')
      | Node(t1,t2) ->
	 let acc, acc' = fn acc acc' t1 in
	 fn acc acc' t2
    end
  in
  let acc, acc' = fn [] [] t in
  List.sort compare acc, List.sort compare acc'

type err_info = {
  mutable max_err_pos:int;
  mutable max_err_buf:buffer;
  mutable max_err_col:int;
  mutable err_msgs: string_tree;
}

let record_error err_info msg str col =
  let pos = Input.line_beginning str + col in
  let pos' = err_info.max_err_pos in
  let c = compare pos pos' in
  if c = 0 then err_info.err_msgs <- msg @@ err_info.err_msgs
  else if c > 0 then
    begin
      err_info.max_err_pos <- pos;
      err_info.max_err_buf <- str;
      err_info.max_err_col <- col;
      err_info.err_msgs <- msg;
    end

type rec_err = buffer -> int -> string_tree -> unit
type rec_err2 = string_tree -> unit

(* phase de lecture d'un caractère, qui ne dépend pas de la bnf *)
let lecture : type a.int -> rec_err -> buffer -> int -> blank -> a pos_tbl -> a final buf_table -> a final buf_table =
  fun id rec_err buf0 pos0 blank elements tbl ->
    if !debug_lvl > 3 then Printf.eprintf "read at line = %d col = %d (%d)\n%!" (line_beginning buf0) pos0 id;
    let buf, pos = blank buf0 pos0 in
    if !debug_lvl > 2 then Printf.eprintf "read after blank line = %d col = %d (%d)\n%!" (line_beginning buf) pos id;
    let tbl = ref tbl in
    Hashtbl.iter (fun _ l -> List.iter (function
    | D {debut; debut_after_blank; fin; stack;acts; rest; full;ignb} ->
       match rest with
       | Next(Term f,rest) ->
	  (try
	     let a, buf, pos = if ignb then f buf0 pos0 else f buf pos in
	     let n = line_beginning buf + pos - line_beginning buf0 - pos0 in
	     let dab = if eq_pos debut fin then (buf,pos) else debut_after_blank in
	      let state =
		(D {debut; debut_after_blank = dab; fin=(buf, pos); stack; shifts = Unit;
		    acts = Something(Lazy.from_val a,acts); rest; full;ignb=false})
	      in
	      tbl := insert_buf buf pos state !tbl
	   with Error msg -> rec_err buf pos msg
           | Give_up msg -> rec_err buf pos (Message msg))
       | IgnNext(Term f,rest) ->
	  (try
	     let a, buf, pos = if ignb then f buf0 pos0 else f buf pos in
	     let n = line_beginning buf + pos - line_beginning buf0 - pos0 in
	     let dab = if eq_pos debut fin then (buf,pos) else debut_after_blank in
	      let state =
		(D {debut; debut_after_blank = dab; fin=(buf, pos); stack; shifts = Unit;
		    acts = Something(Lazy.from_val a,acts); rest; full;ignb=true})
	      in
	      tbl := insert_buf buf pos state !tbl
	   with Error msg -> rec_err buf pos msg
	   | Give_up msg -> rec_err buf pos (Message msg))

       | _ -> ()) l) elements;
    !tbl

(* selectionnne les éléments commençant par un terminal
   ayant la règle donnée *)
type 'b action = { a : 'a.'a rule -> ('a, 'b) element list ref -> unit }

let pop_final : type a b. b dep_pair list ref -> b final -> b action -> unit =
  fun dlr element act ->
    match element with
    | D {rest=rule; acts; full; debut; debut_after_blank; fin; stack;ignb} ->
       (match rule with
       | Next((NonTerm(rules) | RefTerm{contents = rules}),rest) ->
	  (match rest, not (eq_pos debut fin) with
	  | Empty f as rest, true ->
	     List.iter (function C {rest; shifts; acts=acts'; full; debut; stack} ->
	       let c = C {rest; shifts=Shift(f,acts,shifts); acts=acts'; full;
			  debut; debut_after_blank; fin; stack;ignb=false} in
 	       iter_rules (fun r -> act.a r (add_assq r c dlr)) rules) !stack
	  | EmptyPos f as rest, true ->
	     List.iter (function C {rest; shifts; acts=acts'; full; debut; stack} ->
	       let c = C {rest; shifts=ShiftPos(f,acts,shifts); acts=acts'; full;
			  debut; debut_after_blank; fin; stack;ignb=false} in
 	       iter_rules (fun r -> act.a r (add_assq r c dlr)) rules) !stack
	  | rest, _ ->
	     let c = C {rest; acts; shifts=Direct; full; debut; debut_after_blank;
			fin; stack;ignb=false} in
	     iter_rules (fun r -> act.a r (add_assq r c dlr)) rules)
       | IgnNext((NonTerm(rules) | RefTerm{contents = rules}),rest) ->
	  (match rest, not (eq_pos debut fin) with
	  | Empty f as rest, true ->
	     List.iter (function C {rest; shifts; acts=acts'; full; debut; stack} ->
	       let c = C {rest; shifts=Shift(f,acts,shifts); acts=acts'; full;
			  debut; debut_after_blank; fin; stack;ignb=true} in
 	       iter_rules (fun r -> act.a r (add_assq r c dlr)) rules) !stack
	  | EmptyPos f as rest, true ->
	     List.iter (function C {rest; shifts; acts=acts'; full; debut; stack} ->
	       let c = C {rest; shifts=ShiftPos(f,acts,shifts); acts=acts'; full;
			  debut; debut_after_blank; fin; stack;ignb=true} in
 	       iter_rules (fun r -> act.a r (add_assq r c dlr)) rules) !stack
	  | rest, _ ->
	     let c = C {rest; acts; shifts=Direct; full; debut; debut_after_blank;
			fin; stack;ignb=true} in
	     iter_rules (fun r -> act.a r (add_assq r c dlr)) rules)
       | _ -> assert false)

let taille_tables els forward =
  let res = ref 0 in
  Hashtbl.iter (fun _ els -> List.iter (fun el -> res := !res + taille el) els) els;
  iter_buf forward (fun el -> res := !res + taille el);
  !res

(* fait toutes les prédictions et productions pour un element donné et
   comme une prédiction ou une production peut en entraîner d'autres,
   c'est une fonction récursive *)
let rec one_prediction_production
 : type a. rec_err2 -> a dep_pair list ref -> a pos_tbl -> a final -> unit
 = fun rec_err dlr elements element ->
   match element with
  (* prediction (pos, i, ... o NonTerm name::rest_rule) dans la table *)
  | D {debut=i; debut_after_blank=i'; fin=j; acts; stack; rest; full;ignb=ignb0} ->
     match rest with
     | Next((NonTerm (_) | RefTerm(_)),_)
     | IgnNext((NonTerm (_) | RefTerm(_)),_) ->
	let acts =
	  { a = (fun rule stack ->
	    let nouveau = D {shifts = Unit; debut=j; debut_after_blank = j; fin=j; acts = Nothing; stack; rest = rule; full = rule; ignb=ignb0} in
	    let b = add "P" nouveau elements in
	    if b then one_prediction_production rec_err dlr elements nouveau) }
	in pop_final dlr element acts

     (* production	(pos, i, ... o ) dans la table *)
     | Empty a ->
	(try
	   let x = apply_actions acts a in
	  let complete element =
	    match element with
	    | C {debut=k; debut_after_blank=k'; fin=i'; stack=els'; shifts; acts; rest; full;ignb} ->
	      let x = Lazy.from_fun (fun () -> apply_shifts k' i' shifts x) in
	      let nouveau = D {shifts = Unit; debut=k; debut_after_blank=k';
			       acts = Something(x,acts); fin=j; stack=els'; rest; full;ignb=ignb||ignb0} in
	      let b = add "C" nouveau elements in
	      if b then one_prediction_production rec_err dlr elements nouveau
	  in
	  if eq_pos i j then memo_assq full dlr complete;
	  List.iter complete !stack
	 with Give_up msg -> rec_err (Message msg)
	 | Error msg -> rec_err msg)
     | EmptyPos a ->
	(try
	  let a = a (fst i) (snd i) (fst j) (snd j) in
	  let x = apply_actions acts a in
	  let complete element =
	    match element with
	    | C {debut=k; debut_after_blank=k'; fin=i'; stack=els'; shifts; acts; rest; full;ignb} ->
	      let x = Lazy.from_fun (fun () -> apply_shifts k' i' shifts x) in
	      let nouveau = D {shifts = Unit; debut=k; debut_after_blank=k';
			       acts = Something(x,acts); fin=j; stack=els'; rest; full;ignb=ignb||ignb0} in
	      let b = add "C" nouveau elements in
	      if b then one_prediction_production rec_err dlr elements nouveau
	  in
	  if eq_pos i j then memo_assq full dlr complete;
	  List.iter complete !stack
	 with Give_up msg -> rec_err (Message msg)
	 | Error msg -> rec_err msg)
     | Dep f ->
	let rest,acts = match acts with
	  | Nothing -> assert false
	  | Something(g,acts) -> f (Lazy.force g),(acts)
	in
	let nouveau = D {shifts = Unit; debut=i; debut_after_blank=i'; fin=j; acts; stack; rest; full;ignb=ignb0} in
	let b = add "D" nouveau elements in
	if b then one_prediction_production rec_err dlr elements nouveau
     | _ -> ()

(* fait toutes les prédictions productions pour les entrées de la
   table à la position indiquée *)
let prediction_production : type a.rec_err2 -> a pos_tbl -> unit
  = fun rec_err elements ->
    let dlr = ref [] in
    Hashtbl.iter ((fun _ l -> List.iter (fun el -> one_prediction_production rec_err dlr elements el) l))
    elements

exception Parse_error of string * int * int * string list * string list

let c = ref 0
let parse_buffer_aux : type a.bool -> a grammar -> blank -> buffer -> int -> a * buffer * int =
  fun internal main blank buf0 pos0 ->
    let parse_id = incr c; !c in
    (* construction de la table initiale *)
    let err_info =
      { max_err_pos = -1 ; max_err_buf = buf0
      ; max_err_col = -1; err_msgs = TEmpty}
    in
    let elements : a pos_tbl = Hashtbl.create 31 in
    let r0 : a rule = next main idtEmpty in
    let s0 : (a, a) element list ref = ref [] in
    let bp = (buf0,pos0) in
    let _ = add "I" (D {shifts = Unit; debut=bp; fin=bp; debut_after_blank = bp;
			acts = Nothing; stack=s0; rest=r0; full=r0;ignb=false}) elements in
    let pos = ref pos0 and buf = ref buf0 in
    let forward = ref empty_buf in
    let rec_err buf pos msg =
      record_error err_info msg buf pos
    in
    let parse_error () =
      let msgs = err_info.err_msgs in
      if internal then raise (Error msgs) else
	let buf = err_info.max_err_buf in
	let pos = err_info.max_err_col in
	let msg, expected = collect_tree msgs in
	raise (Parse_error (fname buf, line_num buf, pos, msg, expected))
    in
    (* boucle principale *)
    let continue = ref true in
    while !continue do
      if !debug_lvl > 0 then Printf.eprintf "parse_id = %d, pos = %d, taille =%d\n%!"
	parse_id !pos (taille_tables elements !forward);
      prediction_production (rec_err !buf !pos) elements;
      forward := lecture parse_id rec_err !buf !pos blank elements !forward;
      let l =
	try
	  let (buf', pos', l, forward') = pop_firsts_buf !forward in
	  pos := pos';
	  buf := buf';
	  forward := forward';
	  l
	with Not_found -> []
      in
      if l = [] then continue := false else
	begin
	  Hashtbl.clear elements;
	  List.iter (fun s -> ignore (add "L" s elements)) l;
	end
    done;
    prediction_production (rec_err !buf !pos) elements;
  (* on regarde si on a parsé complètement la catégorie initiale *)
    let rec fn : type a.a final list -> a = function
      | [] -> parse_error ()
      | D {debut=(b,i); stack=s1; rest=Empty f; acts = a; full=r1} :: els ->
	 assert(eq_buf b buf0 &&  i = pos0);
	 (match r1 === r0, s1 === s0 with
	 | Eq, Eq -> apply_actions a f
	 | _ -> fn els)
      | _ :: els -> fn els
    in
    let a = fn (try find_pos_tbl elements (buf0,pos0) with Not_found -> []) in
    (a, !buf, !pos)

let partial_parse_buffer : type a.a grammar -> blank -> buffer -> int -> a * buffer * int
  = fun g bl buf pos -> parse_buffer_aux false g bl buf pos

let internal_parse_buffer : type a.a grammar -> blank -> buffer -> int -> a * buffer * int
  = fun g bl buf pos -> parse_buffer_aux true g bl buf pos

let eof : 'a -> 'a grammar
  = fun a ->
    let fn buf pos =
      if is_empty buf pos then (a,buf,pos) else expected "EOF"
    in
    solo fn

let sequence : 'a grammar -> 'b grammar -> ('a -> 'b -> 'c) -> 'c grammar
  = fun l1 l2 f ->
    [next l1 (next l2 (Empty(fun b a -> f a b)))]

let sequence_position : 'a grammar -> 'b grammar -> ('a -> 'b -> buffer -> int -> buffer -> int -> 'c) -> 'c grammar
   = fun l1 l2 f ->
    [next l1 (next l2 (EmptyPos(fun buf pos buf' pos' b a -> f a b buf pos buf' pos')))]

let parse_buffer : 'a grammar -> blank -> buffer -> 'a =
  fun g blank buf ->
    let g = sequence g (eof ()) (fun x _ -> x) in
    let (a, _, _) = partial_parse_buffer g blank buf 0 in
    a

let parse_string ?(filename="") grammar blank str =
  let str = buffer_from_string ~filename str in
  parse_buffer grammar blank str

let partial_parse_string ?(filename="") grammar blank str =
  let str = buffer_from_string ~filename str in
  partial_parse_buffer grammar blank str

let parse_channel ?(filename="") grammar blank ic  =
  let str = buffer_from_channel ~filename ic in
  parse_buffer grammar blank str

let parse_file grammar blank filename  =
  let str = buffer_from_file filename in
  parse_buffer grammar blank str

let fail : string -> 'a grammar
  = fun msg ->
    let fn buf pos =
      unexpected msg
    in
    solo fn

let unset : string -> 'a grammar
  = fun msg ->
    let fn buf pos =
      failwith msg
    in
    solo fn

let declare_grammar name =
  [Next(RefTerm (ref (unset (name ^ " not set"))), idtEmpty)]

let set_grammar : type a.a grammar -> a grammar -> unit = fun p1 p2 ->
  match p1 with
  | [Next(RefTerm(ptr),e)] ->
     (match e === idtEmpty with
     |  Eq -> ptr := p2
     | Neq -> invalid_arg "set_grammar")
  | _ -> invalid_arg "set_grammar"

let char : char -> 'a -> 'a grammar
  = fun c a ->
    let msg = Printf.sprintf "%C" c in
    let fn buf pos =
      let c', buf', pos' = read buf pos in
      if c = c' then (a,buf',pos') else expected msg
    in
    solo fn

let in_charset : charset -> char grammar
  = fun cs ->
    let msg = Printf.sprintf "%s" (String.concat "|" (list_of_charset cs)) in
    let fn buf pos =
      let c, buf', pos' = read buf pos in
      if mem cs c then (c,buf',pos') else expected msg
    in
    solo fn

let any : char grammar
  = let fn buf pos =
      let c', buf', pos' = read buf pos in
      (c',buf',pos')
    in
    solo fn

let debug msg : unit grammar
    = let fn buf pos =
	Printf.eprintf "%s file:%s line:%d col:%d\n%!" msg (fname buf) (line_num buf) pos;
	((), buf, pos)
      in
      solo fn

let string : string -> 'a -> 'a grammar
  = fun s a ->
    let fn buf pos =
      let buf = ref buf in
      let pos = ref pos in
      let len_s = String.length s in
      for i = 0 to len_s - 1 do
        let c, buf', pos' = read !buf !pos in
        if c <> s.[i] then expected s;
        buf := buf'; pos := pos'
      done;
      (a,!buf,!pos)
    in
    solo fn

let regexp : string -> ?name:string -> ((int -> string) -> 'a) -> 'a grammar
  = fun r0 ?(name=String.escaped r0) a ->
    let r = Str.regexp r0 in
    let fn buf pos =
      let l = line buf in
      if pos > String.length l then expected name;
      if string_match r l pos then (
        let f n = matched_group n l in
        let pos' = match_end () in
	let res = try a f with Give_up msg -> unexpected msg in
	(res,buf,pos'))
      else expected name
    in
    solo fn

(* charset is now useless ... will be suppressed soon *)
let black_box : (buffer -> int -> 'a * buffer * int) -> charset -> 'a option -> string -> 'a grammar
  = fun fn _ empty name ->
    match empty with
    | None -> solo fn
    | Some a -> Empty a :: solo fn

let empty : 'a -> 'a grammar = fun a -> [Empty a]

let sequence3 : 'a grammar -> 'b grammar -> 'c grammar -> ('a -> 'b -> 'c -> 'd) -> 'd grammar
  = fun l1 l2 l3 f ->
    [next l1 (next l2 (next l3 (Empty(fun c b a -> f a b c))))]

let fsequence : 'a grammar -> ('a -> 'b) grammar -> 'b grammar
  = fun l1 l2 -> sequence l1 l2 (fun x f -> f x)

let fsequence_position : 'a grammar -> ('a -> buffer -> int -> buffer -> int -> 'b) grammar -> 'b grammar
  = fun l1 l2 -> sequence_position l1 l2 (fun x f -> f x)

let dependent_sequence : 'a grammar -> ('a -> 'b grammar) -> 'b grammar
  = fun l1 f2 ->
    [next l1 (Dep (fun a -> next (f2 a) idtEmpty))]

let iter : 'a grammar grammar -> 'a grammar
  = fun g -> dependent_sequence g (fun x -> x)

let conditional_sequence : 'a grammar -> ('a -> bool) -> 'b grammar -> ('a -> 'b -> 'c) -> 'c grammar
  = fun l1 cond l2 f ->
    let l1 = [next l1 (Empty(fun a -> if cond a then a else raise (Error TEmpty)))] in
    [next l1 (next l2 (Empty(fun b a -> f a b)))]

let apply f g = [next g (Empty f)]

let option : 'a -> 'a grammar -> 'a grammar
  = fun a l -> Empty a::l

let option' = option

let revfixpoint :  'a -> ('a -> 'a) grammar -> 'a grammar
  = fun a f1 ->
    let res = declare_grammar "fixpoint" in
    let _ = set_grammar res
      [Empty (fun x -> x);
       next res (next f1 (Empty(fun f g x -> g (f x))))] in
    apply (fun f -> f a) res

let revfixpoint1 :  'a -> ('a -> 'a) grammar -> 'a grammar
  = fun a f1 ->
    let res = declare_grammar "fixpoint" in
    let _ = set_grammar res
      [next f1 (Empty(fun f x -> f x));
       next res (next f1 (Empty(fun f g x -> g (f x))))] in
    apply (fun f -> f a) res

let fixpoint :  'a -> ('a -> 'a) grammar -> 'a grammar
  = fun a f1 ->
    let res = declare_grammar "fixpoint" in
    let _ = set_grammar res
      [Empty a;
       next res (next f1 (Empty(fun f a -> f a)))] in
    res

let fixpoint1 :  'a -> ('a -> 'a) grammar -> 'a grammar
  = fun a f1 ->
    let res = declare_grammar "fixpoint" in
    let _ = set_grammar res
      [next f1 (Empty(fun f -> f a));
       next res (next f1 (Empty(fun f a -> f a)))] in
    res

let fixpoint' = fixpoint
let fixpoint1' = fixpoint1


let delim g = g

let alternatives : 'a grammar list -> 'a grammar = List.flatten

let alternatives' = alternatives

(* FIXME: optimisation: modify g inside when possible *)
let position g =
  [next g (EmptyPos (fun buf pos buf' pos' a ->
    (fname buf, line_num buf, pos, line_num buf', pos', a)))]

let apply_position f g =
  [next g (EmptyPos (fun b p b' p' a -> f a b p b' p'))]

let print_exception = function
  | Parse_error(fname,l,n,msg, expected) ->
     let expected =
       if expected = [] then "" else
	 Printf.sprintf "'%s' expected" (String.concat "|" expected)
     in
     let msg = if msg = [] then "" else (String.concat "," msg)
     in
     let sep = if msg <> "" && expected <> "" then ", " else "" in
     Printf.eprintf "File %S, line %d, characters %d-%d:\nParse error:%s%s%s\n%!" fname l n n msg sep expected
  | _ -> assert false

let handle_exception f a =
  try f a with Parse_error _ as e -> print_exception e; failwith "No parse."

(* cahcing is useless in decap2 *)
let cache g = g

let active_debug = ref true

let grammar_family ?(param_to_string=fun _ -> "X") name =
  let tbl = Hashtbl.create 31 in
  let is_set = ref None in
  (fun p ->
    try Hashtbl.find tbl p
    with Not_found ->
      let g = declare_grammar (name^"_"^param_to_string p) in
      Hashtbl.replace tbl p g;
      (match !is_set with None -> ()
       | Some f -> set_grammar g (f p));
      g),
  (fun f ->
    if !is_set <> None then invalid_arg ("grammar family "^name^" already set");
    is_set := Some f;
    Hashtbl.iter (fun p r -> set_grammar r (f p)) tbl)

let blank_grammar grammar blank buf pos =
  let save_debug = !debug_lvl in
  debug_lvl := !debug_lvl / 10;
  let (_,buf,pos) = partial_parse_buffer grammar blank buf pos in
  debug_lvl := save_debug;
  (buf,pos)

let accept_empty grammar =
  try
    ignore (parse_string grammar no_blank ""); true
  with
    Parse_error _ -> false

let change_layout : ?new_blank_before:bool -> ?old_blank_after:bool -> 'a grammar -> blank -> 'a grammar
  = fun ?(new_blank_before=true) ?(old_blank_after=true) l1 blank1 ->
    let fn buf pos =
      let (buf, pos) = if new_blank_before then blank1 buf pos else (buf, pos) in
      (* FIXME: new_blank_before = false is not done well ... *)
      let (a,buf,pos) = internal_parse_buffer l1 blank1 buf pos in
      let (buf, pos) = if old_blank_after then (buf,pos) else blank1 buf pos in
      (a,buf,pos)
    in
    solo fn

let ignore_next_blank : 'a grammar -> 'a grammar = fun g ->
  [IgnNext(NonTerm g,idtEmpty)]

let merge _ = failwith "merge unimplemented"
let lists _ = failwith "lists unimplemented"