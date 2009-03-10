open Format

open Lacaml.Impl.D
open Lacaml.Io

open Gpr
open Utils

open Test_kernels.SE_iso
open Gen_data

let main () =
  let sigma2 = noise_sigma2 in

  let epsilon = 10e-6 in

  let module Eval = FITC.Eval in
  let module Deriv = FITC.Deriv in
  let eval_prep_inducing = Eval.Inducing.Prepared.calc inducing_inputs in
  let deriv_prep_inducing = Deriv.Inducing.Prepared.calc eval_prep_inducing in
  let inducing = Deriv.Inducing.calc kernel deriv_prep_inducing in
  let eval_prep_inputs =
    Eval.Inputs.Prepared.calc eval_prep_inducing training_inputs
  in
  let deriv_prep_inputs =
    Deriv.Inputs.Prepared.calc deriv_prep_inducing eval_prep_inputs
  in
  let inputs = Deriv.Inputs.calc inducing deriv_prep_inputs in
  let model = Deriv.Model.calc ~sigma2 inputs in

  let new_kernel =
    let params = Eval.Spec.Kernel.get_params kernel in
    let new_log_ell = params.Cov_se_iso.Params.log_ell +. epsilon in
    let new_params =
      { params with Cov_se_iso.Params.log_ell = new_log_ell }
    in
    Eval.Spec.Kernel.create new_params
  in

  let inducing = Deriv.Inducing.calc new_kernel deriv_prep_inducing in
  let inputs = Deriv.Inputs.calc inducing deriv_prep_inputs in
  let model2 = Deriv.Model.calc ~sigma2 inputs in

  let hyper_model = Deriv.Model.prepare_hyper model in
  let mev, model_log_evidence =
    Deriv.Model.calc_log_evidence hyper_model `Log_ell
  in

  let mf1 = Eval.Model.calc_log_evidence (Deriv.Model.calc_eval model) in
  let mf2 = Eval.Model.calc_log_evidence (Deriv.Model.calc_eval model2) in

  printf "mdlog_evidence: %f\n%!" mev;
  printf "mdfinite:   %f\n%!" ((mf2 -. mf1) /. epsilon);

  let trained = Deriv.Trained.calc model ~targets:training_targets in
  let trained2 = Deriv.Trained.calc model2 ~targets:training_targets in

  let hyper_trained = Deriv.Trained.prepare_hyper trained hyper_model in
  let deriv =
    Deriv.Trained.calc_log_evidence hyper_trained model_log_evidence
  in

  let f1 = Eval.Trained.calc_log_evidence (Deriv.Trained.calc_eval trained) in
  let f2 = Eval.Trained.calc_log_evidence (Deriv.Trained.calc_eval trained2) in

  printf "log evidence: %f\n%!" f1;
  printf "dlog_evidence: %f\n%!" deriv;
  printf "dfinite:   %f\n%!" ((f2 -. f1) /. epsilon)

let () = main ()
