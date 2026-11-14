(* JernOrac, the oracle (standard 10.2).

   jernorac run [-- <arguments>]   runs the package around the current folder: `jern run --Interp`
   jernorac test [<test> ...]      runs a tests folder: `jern test --Interp`
   -C <folder>                     starts from <folder> instead of the current one *)

open Jernorac

let usage () =
  prerr_string "usage: jernorac [-C <folder>] run [-- <arguments>]\n       jernorac [-C <folder>] test [<test> ...]\n";
  exit 2

let () =
  let arguments = List.tl (Array.to_list Sys.argv) in
  let start, arguments =
    match arguments with
    | "-C" :: folder :: rest -> (folder, rest)
    | rest -> (Sys.getcwd (), rest)
  in
  let start = if Filename.is_relative start then Filename.concat (Sys.getcwd ()) start else start in
  match arguments with
  | "run-test" :: folder :: [ test ] -> exit (Package.run ~folder ~files:[ test ])
  | "run" :: rest -> (
      let program_arguments = match rest with "--" :: a -> a | [] -> [] | _ -> usage () in
      Std_library.program_arguments := program_arguments;
      match Package.find_package start with
      | None ->
          prerr_string "jernorac: no Journey.siml in this folder or any folder above it\n";
          exit 2
      | Some folder -> exit (Package.run ~folder ~files:(Package.jern_files folder)))
  | "test" :: only -> (
      match Package.find_package start with
      | None ->
          prerr_string "jernorac: no Journey.siml in this folder or any folder above it\n";
          exit 2
      | Some folder -> exit (Test_runner.run ~folder ~only))
  | _ -> usage ()
