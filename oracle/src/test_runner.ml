(* `jern test --Interp`: in a folder whose Journey.siml says `kind tests`, each .jern file is its
   own program, and its output is compared byte for byte with the .out, .err and .exit beside it
   (D122, standard 10.1a). *)

let cores = 3   (* rule 11 *)

type outcome = { test : string; passed : bool; problems : string list }

let read_or_empty path = if Sys.file_exists path then Package.read_file path else ""

let expected_exit path =
  if Sys.file_exists path then int_of_string_opt (String.trim (Package.read_file path)) else Some 0

(* Each test runs as its own process: `jernorac run-test <folder> <file>`. *)
let start ~executable ~folder ~scratch test =
  let base = Filename.concat scratch (Filename.remove_extension test) in
  let stdout_file = base ^ ".stdout" and stderr_file = base ^ ".stderr" in
  let open_out_file f = Unix.openfile f [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o644 in
  let out = open_out_file stdout_file and err = open_out_file stderr_file in
  let input = Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0 in
  let pid = Unix.create_process executable [| executable; "run-test"; folder; test |] input out err in
  Unix.close out; Unix.close err; Unix.close input;
  (pid, test, stdout_file, stderr_file)

let finish ~folder (test, stdout_file, stderr_file, status) =
  let base = Filename.concat folder (Filename.remove_extension test) in
  let actual_out = read_or_empty stdout_file and actual_err = read_or_empty stderr_file in
  let actual_exit = match status with Unix.WEXITED c -> c | Unix.WSIGNALED s -> 128 + s | Unix.WSTOPPED s -> 128 + s in
  let problems = ref [] in
  let compare_text label expected actual =
    if expected <> actual then
      problems := Printf.sprintf "%s differs\n--- expected\n%s--- got\n%s---" label expected actual :: !problems
  in
  compare_text "stdout" (read_or_empty (base ^ ".out")) actual_out;
  compare_text "stderr" (read_or_empty (base ^ ".err")) actual_err;
  (match expected_exit (base ^ ".exit") with
   | Some e when e = actual_exit -> ()
   | Some e -> problems := Printf.sprintf "exit code: expected %d, got %d" e actual_exit :: !problems
   | None -> problems := "the .exit file doesn't hold a number" :: !problems);
  { test; passed = !problems = []; problems = List.rev !problems }

let run ~(folder : string) ~(only : string list) : int =
  let executable = Sys.executable_name in
  let tests = Package.jern_files folder in
  let tests = if only = [] then tests else List.filter (fun t -> List.exists (fun o -> Filename.remove_extension t = Filename.remove_extension o) only) tests in
  let scratch = Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "jernorac-tests-%d" (Unix.getpid ())) in
  (try Unix.mkdir scratch 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  let pending = ref tests and running = ref [] and outcomes = ref [] in
  (* a test that runs longer than this is stopped and counts as failed, so one endless loop can't hang the run *)
  let limit = match Sys.getenv_opt "JERNORAC_TEST_SECONDS" with Some s -> float_of_string s | None -> 60.0 in
  let started = Hashtbl.create 8 in
  Sys.set_signal Sys.sigalrm (Sys.Signal_handle (fun _ -> ()));
  ignore (Unix.setitimer Unix.ITIMER_REAL { Unix.it_interval = 1.0; it_value = 1.0 });
  while !pending <> [] || !running <> [] do
    while !pending <> [] && List.length !running < cores do
      let test = List.hd !pending in
      pending := List.tl !pending;
      let (pid, _, _, _) as started_test = start ~executable ~folder ~scratch test in
      Hashtbl.replace started pid (Unix.gettimeofday ());
      running := started_test :: !running
    done;
    (* wait for a test to end; a timer interrupts the wait once a second to look at the time limit *)
    let pid, status = try Unix.wait () with Unix.Unix_error (Unix.EINTR, _, _) -> (0, Unix.WEXITED 0) in
    if pid = 0 then begin
      let now = Unix.gettimeofday () in
      List.iter
        (fun (p, test, o, e) ->
          if now -. Hashtbl.find started p > limit then begin
            (try Unix.kill p Sys.sigkill with Unix.Unix_error _ -> ());
            ignore (Unix.waitpid [] p);
            running := List.filter (fun (q, _, _, _) -> q <> p) !running;
            outcomes := { test; passed = false; problems = [ Printf.sprintf "it ran longer than %.0f seconds and was stopped" limit ] } :: !outcomes;
            (try Sys.remove o; Sys.remove e with Sys_error _ -> ())
          end)
        !running
    end
    else
      match List.find_opt (fun (p, _, _, _) -> p = pid) !running with
      | Some (_, test, o, e) ->
          running := List.filter (fun (p, _, _, _) -> p <> pid) !running;
          outcomes := finish ~folder (test, o, e, status) :: !outcomes;
          (try Sys.remove o; Sys.remove e with Sys_error _ -> ())
      | None -> ()
  done;
  ignore (Unix.setitimer Unix.ITIMER_REAL { Unix.it_interval = 0.0; it_value = 0.0 });
  (try Unix.rmdir scratch with Unix.Unix_error _ -> ());
  let outcomes = List.sort (fun a b -> compare a.test b.test) !outcomes in
  let failed = List.filter (fun o -> not o.passed) outcomes in
  List.iter
    (fun o ->
      Printf.printf "FAIL %s\n" o.test;
      List.iter (fun p -> Printf.printf "%s\n" p) o.problems)
    failed;
  Printf.printf "%d passed, %d failed\n" (List.length outcomes - List.length failed) (List.length failed);
  if failed = [] then 0 else 1
