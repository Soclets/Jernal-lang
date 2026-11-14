(* Text helpers: UTF-8 checks and grapheme clusters. *)

let is_valid_utf_8 (text : string) : bool = String.is_valid_utf_8 text

(* The number of grapheme clusters in [text], what a person sees as characters. *)
(* trace: D131 *)
let grapheme_count (text : string) : int =
  Uuseg_string.fold_utf_8 `Grapheme_cluster (fun count _ -> count + 1) 0 text

(* The number of Unicode code points in [text]. *)
(* trace: D130 *)
let code_point_count (text : string) : int =
  let rec go index count =
    if index >= String.length text then count
    else
      let decoded = String.get_utf_8_uchar text index in
      go (index + Uchar.utf_decode_length decoded) (count + 1)
  in
  go 0 0

(* The lines of a file's text, split on "\n", each without its "\r" if it ended in "\r\n". *)
let lines_of (text : string) : string array =
  let pieces = String.split_on_char '\n' text in
  let strip line =
    let length = String.length line in
    if length > 0 && line.[length - 1] = '\r' then String.sub line 0 (length - 1) else line
  in
  Array.of_list (List.map strip pieces)

(* The byte index where [needle] first appears in [text]. *)
let find_substring (text : string) (needle : string) : int option =
  let n = String.length text and m = String.length needle in
  let rec go i = if i + m > n then None else if String.sub text i m = needle then Some i else go (i + 1) in
  go 0
