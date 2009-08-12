open Format

open Lacaml.Impl.D
open Lacaml.Io

open Gpr
open Utils

open Test_kernels.SE_iso
open Gen_data

let find_sigma2 () =
  let module Eval = FITC.Eval in
  let module Deriv = FITC.Deriv in
  let inducing_points =
    Eval.Inducing.choose_n_random_inputs kernel ~n_inducing training_inputs
  in
  let inducing = Deriv.Inducing.calc kernel inducing_points in
  let inputs = Deriv.Inputs.calc inducing training_inputs in
  let eval_inputs = Deriv.Inputs.calc_eval inputs in

  let model_ref = ref None in

  let multim_f ~x =
    let sigma2 = exp x.{0} in
    let model =
      match !model_ref with
      | None ->
          let model = Eval.Model.calc ~sigma2 eval_inputs in
          model_ref := Some model;
          model
      | Some model -> Eval.Model.update_sigma2 model sigma2
    in
    let trained = Eval.Trained.calc model ~targets:training_targets in
    let log_evidence = Eval.Trained.calc_log_evidence trained in
    -. log_evidence
  in

  let dmodel_ref = ref None in

  let multim_dcommon ~x ~g =
    let sigma2 = exp x.{0} in
    let dmodel =
      match !dmodel_ref with
      | None ->
          let dmodel = Deriv.Model.calc ~sigma2 inputs in
          dmodel_ref := Some dmodel;
          dmodel
      | Some dmodel -> Deriv.Model.update_sigma2 dmodel sigma2
    in
    let trained = Deriv.Trained.calc dmodel ~targets:training_targets in
    let dlog_evidence = Deriv.Trained.calc_log_evidence_sigma2 trained in
    g.{0} <- -. dlog_evidence *. sigma2;
    trained
  in

  let multim_df ~x ~g =
    ignore (multim_dcommon ~x ~g)
  in

  let multim_fdf ~x ~g =
    let trained = multim_dcommon ~x ~g in
    let log_evidence =
      Eval.Trained.calc_log_evidence (Deriv.Trained.calc_eval trained)
    in
    -. log_evidence
  in

  let multim_fun_fdf =
    {
      Gsl_fun.
      multim_f = multim_f;
      multim_df = multim_df;
      multim_fdf = multim_fdf;
    }
  in

  let init = Gsl_vector.create ~init:(log 1.) 1 in

  let module Gd = Gsl_multimin.Deriv in
  let mumin =
    Gd.make Gd.VECTOR_BFGS2 1
      multim_fun_fdf ~x:init ~step:1e-3 ~tol:1e-4
  in
  let x = Gsl_vector.create 1 in
  let rec loop last_log_evidence =
    let nll = Gd.minimum ~x mumin in
    let log_evidence = -. nll in
    let diff = abs_float (1. -. (log_evidence /. last_log_evidence)) in
    printf "diff: %f\n%!" diff;
    if diff < 0.001 then -. nll, exp x.{0}
    else (
      printf "log evidence: %f\n%!" log_evidence;
      Gd.iterate mumin;
      loop log_evidence)
  in
  loop neg_infinity

let main () =
  let log_evidence, sigma2 = find_sigma2 () in
  printf "log evidence: %.15f  sigma2: %.15f\n" log_evidence sigma2

let () = main ()
