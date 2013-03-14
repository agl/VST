Load loadpath.

(*CompCert imports*)
Require Import Events.
Require Import Memory.
Require Import Coqlib.
Require Import Values.
Require Import Maps.
Require Import Integers.
Require Import AST.
Require Import Globalenvs.

Require Import Axioms.
Require Import sepcomp.mem_lemmas. (*TODO: Is this import needed?*)
Require Import sepcomp.core_semantics.

Definition val_inject_opt (j: meminj) (v1 v2: option val) :=
  match v1, v2 with Some v1', Some v2' => val_inject j v1' v2'
  | None, None => True
  | _, _ => False
  end.

Definition val_has_type_opt' (v: option val) (ty: typ) :=
 match v with
 | None => True
 | Some v' => Val.has_type v' ty
 end.

Definition val_has_type_opt (v: option val) (sig: signature) :=
  val_has_type_opt' v (proj_sig_res sig).

(** * Here we present a module type which expresses the sort of
   forward simulation lemmas we have available.  The idea is that
   these lemmas would be used in the individual compiler passes and
   the composition lemma would be used to build the main lemma. 

   First, a forward simulation for passes which do not alter the
   memory layout at all. *)

Module Forward_simulation_eq. Section Forward_simulation_equals. 
  Context {M G1 C1 D1 G2 C2 D2:Type}
          {Sem1 : CoreSemantics G1 C1 M D1}
          {Sem2 : CoreSemantics G2 C2 M D2}

          {ge1:G1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

  Record Forward_simulation_equals :=
  { core_data:Type;

    match_core : core_data -> C1 -> C2 -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;

    core_diagram : 
      forall st1 m st1' m', corestep Sem1 ge1 st1 m st1' m' ->
      forall d st2, match_core d st1 st2 ->
        exists st2', exists d',
          match_core d' st1' st2' /\
          ((corestep_plus Sem2 ge2 st2 m st2' m') \/
            corestep_star Sem2 ge2 st2 m st2' m' /\
            core_ord d' d);

    core_initial : forall v1 v2 sig,
      In (v1,v2,sig) entry_points ->
        forall vals,
          Forall2 (Val.has_type) vals (sig_args sig) ->
          exists cd, exists c1, exists c2,
            make_initial_core Sem1 ge1 v1 vals = Some c1 /\
            make_initial_core Sem2 ge2 v2 vals = Some c2 /\
            match_core cd c1 c2;

    core_halted : forall cd c1 c2 v,
      match_core cd c1 c2 ->
      safely_halted Sem1 c1 = Some v ->
      safely_halted Sem2 c2 = Some v;

    core_at_external : 
      forall d st1 st2 e args ef_sig,
        match_core d st1 st2 ->
        at_external Sem1 st1 = Some (e,ef_sig,args) ->
        ( at_external Sem2 st2 = Some (e,ef_sig,args) /\
          Forall2 Val.has_type args (sig_args ef_sig) );

    core_after_external :
      forall d st1 st2 ret e args ef_sig,
        match_core d st1 st2 ->
        at_external Sem1 st1 = Some (e,ef_sig,args) ->
        at_external Sem2 st2 = Some (e,ef_sig,args) ->
        Forall2 Val.has_type args (sig_args ef_sig) ->
        Val.has_type ret (proj_sig_res ef_sig) ->
        exists st1', exists st2', exists d',
          after_external Sem1 (Some ret) st1 = Some st1' /\
          after_external Sem2 (Some ret) st2 = Some st2' /\
          match_core d' st1' st2' }.

End Forward_simulation_equals. 

(*Question: Does this declaration take effect after module import?*)
Implicit Arguments Forward_simulation_equals [[G1] [C1] [G2] [C2]]. 

End Forward_simulation_eq.

(** * Next, an axiom for passes that allow the memory to undergo extension. *)

Module Forward_simulation_ext. Section Forward_simulation_extends. 
  Context {G1 C1 D1 G2 C2 D2:Type}
          {Sem1: RelyGuaranteeSemantics G1 C1 D1}
          {Sem2: RelyGuaranteeSemantics  G2 C2 D2}

          {ge1:G1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

  Record Forward_simulation_extends := 
  { core_data : Type;

    match_state : core_data -> C1 -> mem -> C2 -> mem -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;

    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 m2,
        match_state cd st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd',
          match_state cd' st1' m1' st2' m2' /\
          mem_unchanged_on (fun b ofs => 
            loc_out_of_bounds m1 b ofs /\ ~private_block Sem1 st1 b) m1 m1' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
      In (v1,v2,sig) entry_points ->
        forall vals vals' m1 m2,
          Forall2 Val.lessdef vals vals' ->
          Forall2 (Val.has_type) vals' (sig_args sig) ->
          Mem.extends m1 m2 ->
          exists cd, exists c1, exists c2,
            make_initial_core Sem1 ge1 v1 vals = Some c1 /\
            make_initial_core Sem2 ge2 v2 vals' = Some c2 /\
            match_state cd c1 m1 c2 m2;

    core_halted : 
      forall cd st1 m1 st2 m2 v1,
        match_state cd st1 m1 st2 m2 ->
        safely_halted Sem1 st1 = Some v1 ->
        exists v2, Val.lessdef v1 v2 /\
            safely_halted Sem2 st2 = Some v2 /\
            Mem.extends m1 m2;

    core_at_external : 
      forall cd st1 m1 st2 m2 e vals1 ef_sig,
        match_state cd st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        exists vals2,
          Mem.extends m1 m2 /\
          Forall2 Val.lessdef vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args ef_sig) /\
          at_external Sem2 st2 = Some (e,ef_sig,vals2);

    core_after_external :
      forall cd st1 st2 m1 m2 e vals1 vals2 ret1 ret2 m1' m2' ef_sig,
        match_state cd st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        at_external Sem2 st2 = Some (e,ef_sig,vals2) ->

        Forall2 Val.lessdef vals1 vals2 ->
        Forall2 (Val.has_type) vals2 (sig_args ef_sig) ->
        mem_forward m1 m1' ->
        mem_forward m2 m2' ->

        mem_unchanged_on (loc_out_of_bounds m1) m2 m2' -> 
       (*i.e., spill-locations didn't change*)
        Val.lessdef ret1 ret2 ->
        Mem.extends m1' m2' ->

        Val.has_type ret2 (proj_sig_res ef_sig) -> 

        exists st1', exists st2', exists cd',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' st1' m1' st2' m2' }.

End Forward_simulation_extends.

Implicit Arguments Forward_simulation_extends [[G1] [C1] [G2] [C2]].

End Forward_simulation_ext.

(** Perhaps the "Coop" versions of each record should become the
   standard versions everywhere? *)

Module Coop_forward_simulation_ext. Section Forward_simulation_extends. 
  Context {G1 C1 D1 G2 C2 D2:Type}
          {Sem1 : CoopCoreSem G1 C1 D1}
          {Sem2 : CoopCoreSem  G2 C2 D2}

          {ge1:G1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

  Record Forward_simulation_extends :=
  { core_data : Type;

    match_state : core_data -> C1 -> mem -> C2 -> mem -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;

    (*Matching memories should be well-defined ie not contain values
        with invalid/"dangling" block numbers*)
    match_memwd: forall d c1 m1 c2 m2,  match_state d c1 m1 c2 m2 -> 
      (mem_wd m1 /\ mem_wd m2);

    (*The following axiom could be strengthened to extends m1 m2*)
    match_validblocks: forall d c1 m1 c2 m2,  match_state d c1 m1 c2 m2 -> 
      forall b, Mem.valid_block m1 b <-> Mem.valid_block m2 b;

    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 m2,
        match_state cd st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd',
          match_state cd' st1' m1' st2' m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
      In (v1,v2,sig) entry_points ->
        forall vals vals' m1 m2,
          Forall2 Val.lessdef vals vals' ->
          Forall2 (Val.has_type) vals' (sig_args sig) ->
          Mem.extends m1 m2 ->
          mem_wd m1 -> mem_wd m2 ->
          exists cd, exists c1, exists c2,
            make_initial_core Sem1 ge1 v1 vals = Some c1 /\
            make_initial_core Sem2 ge2 v2 vals' = Some c2 /\
            match_state cd c1 m1 c2 m2;

    core_halted : 
      forall cd st1 m1 st2 m2 v1,
        match_state cd st1 m1 st2 m2 ->
        safely_halted Sem1 st1 = Some v1 -> val_valid v1 m1 ->
        exists v2, Val.lessdef v1 v2 /\
            safely_halted Sem2 st2 = Some v2 /\
            Mem.extends m1 m2 /\ val_valid v2 m2;

    core_at_external : 
      forall cd st1 m1 st2 m2 e vals1 ef_sig,
        match_state cd st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        (forall v1, In v1 vals1 -> val_valid v1 m1) -> 
        exists vals2,
          Mem.extends m1 m2 /\
          Forall2 Val.lessdef vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args ef_sig) /\
          at_external Sem2 st2 = Some (e,ef_sig,vals2) /\
          (forall v2, In v2 vals2 -> val_valid v2 m2);

    core_after_external :
      forall cd st1 st2 m1 m2 e vals1 vals2 ret1 ret2 m1' m2' ef_sig,
        match_state cd st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        (forall v1, In v1 vals1 -> val_valid v1 m1) -> 
        at_external Sem2 st2 = Some (e,ef_sig,vals2) ->

        Forall2 Val.lessdef vals1 vals2 ->
        Forall2 (Val.has_type) vals2 (sig_args ef_sig) ->
        mem_forward m1 m1' ->
        mem_forward m2 m2' ->

        mem_unchanged_on (loc_out_of_bounds m1) m2 m2' -> 
        (*i.e., spill-locations didn't change*)
        Val.lessdef ret1 ret2 ->
        Mem.extends m1' m2' ->

        Val.has_type ret2 (proj_sig_res ef_sig) -> 

        mem_wd m1' -> mem_wd m2' -> val_valid ret1 m1' -> val_valid ret2 m2' ->

        exists st1', exists st2', exists cd',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' st1' m1' st2' m2' }.
End Forward_simulation_extends.

Implicit Arguments Forward_simulation_extends [[G1] [C1] [G2] [C2]].

End Coop_forward_simulation_ext.

(** An axiom for passes that use memory injections. *)

Module Forward_simulation_inj. Section Forward_simulation_inject. 
  Context {F1 V1 C1 D1 G2 C2 D2:Type}
          {Sem1 : RelyGuaranteeSemantics (Genv.t F1 V1) C1 D1}
          {Sem2 : RelyGuaranteeSemantics G2 C2 D2}
          {ge1: Genv.t F1 V1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

  Record Forward_simulation_inject := 
  { core_data : Type;
    match_state : core_data -> meminj -> C1 -> mem -> C2 -> mem -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;
    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 j m2,
        match_state cd j st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists j',
          inject_incr j j' /\
          inject_separated j j' m1 m2 /\
          match_state cd' j' st1' m1' st2' m2' /\
          mem_unchanged_on (fun b ofs => 
            loc_unmapped j b ofs /\ ~private_block Sem1 st1 b) m1 m1' /\
          mem_unchanged_on (fun b ofs => 
            loc_out_of_reach j m1 b ofs /\ ~private_block Sem2 st2 b) m2 m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
       In (v1,v2,sig) entry_points -> 
       forall vals1 c1 m1 j vals2 m2,
          make_initial_core Sem1 ge1 v1 vals1 = Some c1 ->
          Mem.inject j m1 m2 -> 
          Forall2 (val_inject j) vals1 vals2 ->
          Forall2 (Val.has_type) vals2 (sig_args sig) ->
          exists cd, exists c2, 
            make_initial_core Sem2 ge2 v2 vals2 = Some c2 /\
            match_state cd j c1 m1 c2 m2;

    core_halted : forall cd j c1 m1 c2 m2 v1 rty,
      match_state cd j c1 m1 c2 m2 ->
      safely_halted Sem1 c1 = Some v1 ->
      Val.has_type v1 rty -> 
      exists v2, val_inject j v1 v2 /\
          safely_halted Sem2 c2 = Some v2 /\
          Val.has_type v2 rty /\
          Mem.inject j m1 m2;

    core_at_external : 
      forall cd j st1 m1 st2 m2 e vals1 sig,
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,sig,vals1) ->
        ( Mem.inject j m1 m2 /\
          meminj_preserves_globals ge1 j /\ 
          exists vals2, Forall2 (val_inject j) vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args (ef_sig e)) /\
          at_external Sem2 st2 = Some (e,sig,vals2));

    core_after_external :
      forall cd j j' st1 st2 m1 e vals1 ret1 m1' m2 m2' ret2 sig,
        Mem.inject j m1 m2->
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,sig,vals1) ->
        meminj_preserves_globals ge1 j -> 

        inject_incr j j' ->
        inject_separated j j' m1 m2 ->
        Mem.inject j' m1' m2' ->
        val_inject_opt j' ret1 ret2 ->

         mem_forward m1 m1'  -> 
         mem_unchanged_on (fun b ofs => 
           loc_unmapped j b ofs /\ private_block Sem1 st1 b) m1 m1' ->
         mem_forward m2 m2' -> 
         mem_unchanged_on (fun b ofs => 
           loc_out_of_reach j m1 b ofs /\ private_block Sem2 st2 b) m2 m2' ->
         val_has_type_opt' ret1 (proj_sig_res (ef_sig e)) -> 
         val_has_type_opt' ret2 (proj_sig_res (ef_sig e)) -> 

        exists cd', exists st1', exists st2',
          after_external Sem1 ret1 st1 = Some st1' /\
          after_external Sem2 ret2 st2 = Some st2' /\
          match_state cd' j' st1' m1' st2' m2' }.

End Forward_simulation_inject. 

Implicit Arguments Forward_simulation_inject [[F1][V1] [C1] [G2] [C2]].

End Forward_simulation_inj.

Module Coop_forward_simulation_inj. Section Forward_simulation_inject. 
  Context {F1 V1 C1 D1 G2 C2 D2:Type}
          {Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem D1}
          {Sem2 : CoreSemantics G2 C2 mem D2}
          {ge1: Genv.t F1 V1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}.

  Record Forward_simulation_inject := 
  { core_data : Type;
    match_state : core_data -> meminj -> C1 -> mem -> C2 -> mem -> Prop;
    core_ord : core_data -> core_data -> Prop;
    core_ord_wf : well_founded core_ord;

    (*Matching memories should be well-defined ie not contain values
        with invalid/"dangling" block numbers*)
    match_memwd: forall d j c1 m1 c2 m2,  match_state d j c1 m1 c2 m2 -> 
               (mem_wd m1 /\ mem_wd m2);

    (*The following axiom could be strengthened to inject j m1 m2*)
    match_validblocks: forall d j c1 m1 c2 m2,  match_state d j c1 m1 c2 m2 -> 
          forall b1 b2 ofs, j b1 = Some(b2,ofs) -> 
               (Mem.valid_block m1 b1 /\ Mem.valid_block m2 b2);

    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 j m2,
        match_state cd j st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists j',
          inject_incr j j' /\
          inject_separated j j' m1 m2 /\
          match_state cd' j' st1' m1' st2' m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
       In (v1,v2,sig) entry_points -> 
       forall vals1 c1 m1 j vals2 m2,
          make_initial_core Sem1 ge1 v1 vals1 = Some c1 ->
          Mem.inject j m1 m2 -> 
          mem_wd m1 -> mem_wd m2 ->
          (*Is this line needed?? (forall w1 w2 sigg, In (w1,w2,sigg)
           entry_points -> val_inject j w1 w2) ->*) Forall2
           (val_inject j) vals1 vals2 ->

          Forall2 (Val.has_type) vals2 (sig_args sig) ->
          exists cd, exists c2, 
            make_initial_core Sem2 ge2 v2 vals2 = Some c2 /\
            match_state cd j c1 m1 c2 m2;

    core_halted : forall cd j c1 m1 c2 m2 v1,
      match_state cd j c1 m1 c2 m2 ->
      safely_halted Sem1 c1 = Some v1 ->
      val_valid v1 m1 ->
      exists v2, val_inject j v1 v2 /\
        safely_halted Sem2 c2 = Some v2 /\
        Mem.inject j m1 m2 /\ val_valid v2 m2;

    core_at_external : 
      forall cd j st1 m1 st2 m2 e vals1 ef_sig,
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        (forall v1, In v1 vals1 -> val_valid v1 m1) ->
        ( Mem.inject j m1 m2 /\
          meminj_preserves_globals ge1 j /\ 
          exists vals2, Forall2 (val_inject j) vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args ef_sig) /\
          at_external Sem2 st2 = Some (e,ef_sig,vals2) /\
          (forall v2, In v2 vals2 -> val_valid v2 m2));

    core_after_external :
      forall cd j j' st1 st2 m1 e vals1 ret1 m1' m2 m2' ret2 ef_sig,
        Mem.inject j m1 m2->
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,ef_sig,vals1) ->
        (forall v1, In v1 vals1 -> val_valid v1 m1) ->
        meminj_preserves_globals ge1 j -> 

        inject_incr j j' ->
        inject_separated j j' m1 m2 ->
        Mem.inject j' m1' m2' ->
        val_inject j' ret1 ret2 ->

         mem_forward m1 m1'  -> 
         mem_unchanged_on (loc_unmapped j) m1 m1' ->
         mem_forward m2 m2' -> 
         mem_unchanged_on (loc_out_of_reach j m1) m2 m2' ->
         Val.has_type ret2 (proj_sig_res ef_sig) -> 

        mem_wd m1' -> mem_wd m2' -> val_valid ret1 m1' -> val_valid ret2 m2' ->

        exists cd', exists st1', exists st2',
          after_external Sem1 (Some ret1) st1 = Some st1' /\
          after_external Sem2 (Some ret2) st2 = Some st2' /\
          match_state cd' j' st1' m1' st2' m2'
    }.

End Forward_simulation_inject. 

Implicit Arguments Forward_simulation_inject [[F1][V1] [C1] [G2] [C2]].

End Coop_forward_simulation_inj.

(* A variation of Forward_simulation_inj that exposes core_data and match_state *)

Module Forward_simulation_inj_exposed. Section Forward_simulation_inject. 
  Context {F1 V1 C1 D1 G2 C2 D2:Type}
          {Sem1 : RelyGuaranteeSemantics (Genv.t F1 V1) C1 D1}
          {Sem2 : RelyGuaranteeSemantics G2 C2 D2}

          {ge1: Genv.t F1 V1}
          {ge2:G2}
          {entry_points : list (val * val * signature)}
          {core_data : Type}
          {match_state : core_data -> meminj -> C1 -> mem -> C2 -> mem -> Prop}
          {core_ord : core_data -> core_data -> Prop}.

  Record Forward_simulation_inject := 
  { core_ord_wf : well_founded core_ord;
    core_diagram : 
      forall st1 m1 st1' m1', corestep Sem1 ge1 st1 m1 st1' m1' ->
      forall cd st2 j m2,
        match_state cd j st1 m1 st2 m2 ->
        exists st2', exists m2', exists cd', exists j',
          inject_incr j j' /\
          inject_separated j j' m1 m2 /\
          match_state cd' j' st1' m1' st2' m2' /\
          mem_unchanged_on (fun b ofs => 
            loc_unmapped j b ofs /\ ~private_block Sem1 st1 b) m1 m1' /\
          mem_unchanged_on (fun b ofs => 
            loc_out_of_reach j m1 b ofs /\ ~private_block Sem2 st2 b) m2 m2' /\
          ((corestep_plus Sem2 ge2 st2 m2 st2' m2') \/
            corestep_star Sem2 ge2 st2 m2 st2' m2' /\
            core_ord cd' cd);

    core_initial : forall v1 v2 sig,
       In (v1,v2,sig) entry_points -> 
       forall vals1 c1 m1 j vals2 m2,
          make_initial_core Sem1 ge1 v1 vals1 = Some c1 ->
          Mem.inject j m1 m2 -> 
           Forall2 (val_inject j) vals1 vals2 ->
          Forall2 (Val.has_type) vals2 (sig_args sig) ->
          exists cd, exists c2, 
            make_initial_core Sem2 ge2 v2 vals2 = Some c2 /\
            match_state cd j c1 m1 c2 m2;

    core_halted : forall cd j c1 m1 c2 m2 v1 rty,
      match_state cd j c1 m1 c2 m2 ->
      safely_halted Sem1 c1 = Some v1 ->
      Val.has_type v1 rty -> 
      exists v2, val_inject j v1 v2 /\
        safely_halted Sem2 c2 = Some v2 /\
        Val.has_type v2 rty /\
        Mem.inject j m1 m2;

    core_at_external : 
      forall cd j st1 m1 st2 m2 e vals1 sig,
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,sig,vals1) ->
        ( Mem.inject j m1 m2 /\
          meminj_preserves_globals ge1 j /\ 
          exists vals2, Forall2 (val_inject j) vals1 vals2 /\
          Forall2 (Val.has_type) vals2 (sig_args (ef_sig e)) /\
          at_external Sem2 st2 = Some (e,sig,vals2));

    core_after_external :
      forall cd j j' st1 st2 m1 e vals1 ret1 m1' m2 m2' ret2 sig,
        Mem.inject j m1 m2->
        match_state cd j st1 m1 st2 m2 ->
        at_external Sem1 st1 = Some (e,sig,vals1) ->
        meminj_preserves_globals ge1 j -> 

        inject_incr j j' ->
        inject_separated j j' m1 m2 ->
        Mem.inject j' m1' m2' ->
        val_inject_opt j' ret1 ret2 ->

         mem_forward m1 m1'  -> 
         mem_unchanged_on (fun b ofs => 
           loc_unmapped j b ofs /\ private_block Sem1 st1 b) m1 m1' ->
         mem_forward m2 m2' -> 
         mem_unchanged_on (fun b ofs => 
           loc_out_of_reach j m1 b ofs /\ private_block Sem2 st2 b) m2 m2' ->
         val_has_type_opt' ret1 (proj_sig_res (ef_sig e)) -> 
         val_has_type_opt' ret2 (proj_sig_res (ef_sig e)) -> 

        exists cd', exists st1', exists st2',
          after_external Sem1 ret1 st1 = Some st1' /\
          after_external Sem2 ret2 st2 = Some st2' /\
          match_state cd' j' st1' m1' st2' m2'
    }.

End Forward_simulation_inject. 

Implicit Arguments Forward_simulation_inject [[F1][V1] [C1] [G2] [C2]].

End Forward_simulation_inj_exposed.

Lemma Forward_simulation_inj_exposed_hidden: 
  forall (F1 V1 C1 D1 G2 C2 D2: Type) 
   (csemS: RelyGuaranteeSemantics (Genv.t F1 V1) C1 D1)
   (csemT: RelyGuaranteeSemantics G2 C2 D2) ge1 ge2 
   entry_points core_data match_state core_ord,
  Forward_simulation_inj_exposed.Forward_simulation_inject D1 D2 csemS csemT ge1 ge2
    entry_points core_data match_state core_ord -> 
  Forward_simulation_inj.Forward_simulation_inject D1 D2 csemS csemT ge1 ge2 entry_points.
Proof.
intros until core_ord; intros []; intros.
solve[eapply @Forward_simulation_inj.Build_Forward_simulation_inject 
 with (core_data := core_data) (match_state := match_state); eauto].
Qed.

Lemma Forward_simulation_inj_hidden_exposed:
  forall (F1 V1 C1 D1 G2 C2 D2: Type) 
   (csemS: RelyGuaranteeSemantics (Genv.t F1 V1) C1 D1)
   (csemT: RelyGuaranteeSemantics G2 C2 D2) ge1 ge2 entry_points,
  Forward_simulation_inj.Forward_simulation_inject D1 D2 csemS csemT ge1 ge2 entry_points -> 
  {core_data: Type & 
  {match_state: core_data -> meminj -> C1 -> mem -> C2 -> mem -> Prop &
  {core_ord: core_data -> core_data -> Prop & 
    Forward_simulation_inj_exposed.Forward_simulation_inject D1 D2 csemS csemT ge1 ge2
    entry_points core_data match_state core_ord}}}.
Proof.
intros until entry_points; intros []; intros.
solve[eexists; eexists; eexists;
 eapply @Forward_simulation_inj_exposed.Build_Forward_simulation_inject; eauto].
Qed.

Lemma forall_inject_val_list_inject: 
  forall j args args' (H:Forall2 (val_inject j) args args' ), 
    val_list_inject j args args'.
Proof.
intros j args.
induction args; intros;  inv H; constructor; eauto.
Qed. 

Lemma val_list_inject_forall_inject: 
  forall j args args' (H:val_list_inject j args args'), 
    Forall2 (val_inject j) args args' .
Proof.
intros j args.
induction args; intros;  inv H; constructor; eauto.
Qed. 

Lemma forall_lessdef_val_listless: 
  forall args args' (H: Forall2 Val.lessdef args args'), 
    Val.lessdef_list args args' .
Proof.
intros args.
induction args; intros;  inv H; constructor; eauto.
Qed. 

Lemma val_listless_forall_lessdef: 
  forall args args' (H:Val.lessdef_list args args'), 
    Forall2 Val.lessdef args args' .
Proof.
intros args.
induction args; intros;  inv H; constructor; eauto.
Qed. 

Module CompilerCorrectness.

Definition globvar_eq {V1 V2: Type} (v1:globvar V1) (v2:globvar V2) :=
  match v1, v2 with 
  | mkglobvar _ init1 readonly1 volatile1, 
    mkglobvar _ init2 readonly2 volatile2 =>
    init1 = init2 /\ readonly1 =  readonly2 /\ volatile1 = volatile2
  end.

Inductive external_description :=
| extern_func: signature -> external_description
| extern_globvar: external_description.

Definition entryPts_ok  {F1 V1 F2 V2:Type} 
  (P1 : AST.program F1 V1)    (P2 : AST.program F2 V2) 
  (ExternIdents: list (ident * external_description)) 
  (entryPts: list (val * val * signature)): Prop :=
  forall e d, In (e,d) ExternIdents ->
    exists b, Genv.find_symbol  (Genv.globalenv P1) e = Some b /\
      Genv.find_symbol (Genv.globalenv P2) e = Some b /\
      match d with
        extern_func sig => In (Vptr b Int.zero,Vptr b Int.zero, sig) entryPts /\
        exists f1, exists f2, Genv.find_funct_ptr (Genv.globalenv P1) b = Some f1 /\ 
          Genv.find_funct_ptr (Genv.globalenv P2) b = Some f2
        | extern_globvar  => exists v1, exists v2, 
          Genv.find_var_info (Genv.globalenv P1) b = Some v1 /\
          Genv.find_var_info (Genv.globalenv P2) b = Some v2 /\
          globvar_eq v1 v2
      end.

Definition entryPts_inject_ok {F1 V1 F2 V2:Type} 
  (P1 : AST.program F1 V1) (P2 : AST.program F2 V2) (j: meminj)
  (ExternIdents : list (ident * external_description)) 
  (entryPts: list (val * val * signature)): Prop :=
  forall e d, In (e,d) ExternIdents ->
    exists b1, exists b2, Genv.find_symbol (Genv.globalenv P1) e = Some b1 /\
      Genv.find_symbol (Genv.globalenv P2) e = Some b2 /\
      j b1 = Some(b2,0) /\
      match d with
      | extern_func sig => 
        In (Vptr b1 Int.zero,Vptr b2 Int.zero, sig) entryPts /\
        exists f1, exists f2, 
          Genv.find_funct_ptr (Genv.globalenv P1) b1 = Some f1 /\ 
          Genv.find_funct_ptr (Genv.globalenv P2) b2 = Some f2
      | extern_globvar => 
        exists v1, exists v2,
          Genv.find_var_info  (Genv.globalenv P1) b1 = Some v1 /\
          Genv.find_var_info  (Genv.globalenv P2) b2 = Some v2 /\
          globvar_eq v1 v2
      end.

Definition externvars_ok  {F1 V1:Type}  (P1 : AST.program F1 V1) 
  (ExternIdents : list (ident * external_description)) : Prop :=
  forall b v, Genv.find_var_info  (Genv.globalenv P1) b = Some v -> 
    exists e, Genv.find_symbol (Genv.globalenv P1) e = Some b /\ 
      In (e,extern_globvar) ExternIdents.

Definition GenvHyp {F1 V1 F2 V2} 
  (P1 : AST.program F1 V1) (P2 : AST.program F2 V2): Prop :=
  (forall id : ident,
    Genv.find_symbol (Genv.globalenv P2) id =
    Genv.find_symbol (Genv.globalenv P1) id) /\
  (forall b : block,
    block_is_volatile (Genv.globalenv P2) b =
    block_is_volatile (Genv.globalenv P1) b).

Inductive core_correctness (I: forall F C V  
  (Sem : CoreSemantics (Genv.t F V) C mem (list (ident * globdef F V))) 
  (P : AST.program F V),Prop)
  (ExternIdents: list (ident * external_description)):
  forall (F1 C1 V1 F2 C2 V2:Type)
    (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
    (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
    (P1 : AST.program F1 V1)
    (P2 : AST.program F2 V2), Type :=
    corec_eq : forall  (F1 C1 V1 F2 C2 V2:Type)
      (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
      (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
      (P1 : AST.program F1 V1)
      (P2 : AST.program F2 V2)
      (Eq_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
        (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs)
          /\ m1 = m2))
      entrypoints
      (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
      (R:Forward_simulation_eq.Forward_simulation_equals _ _ _ Sem1 Sem2 
        (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints), 
      prog_main P1 = prog_main P2 -> 
      (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
      GenvHyp P1 P2 ->
      I _ _ _  Sem1 P1 -> I _ _ _  Sem2 P2 -> 
      core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
| corec_ext: forall (F1 C1 V1 F2 C2 V2:Type)
  (Sem1 : RelyGuaranteeSemantics (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
  (Sem2 : RelyGuaranteeSemantics (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
  (P1 : AST.program F1 V1)
  (P2 : AST.program F2 V2)
  (Extends_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
    (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs) 
      /\ Mem.extends m1 m2))
  entrypoints
  (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
  (R:Forward_simulation_ext.Forward_simulation_extends _ _ Sem1 Sem2 
    (Genv.globalenv P1) (Genv.globalenv P2) entrypoints),
  prog_main P1 = prog_main P2 -> 
  (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
  GenvHyp P1 P2 ->
  I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
  core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2

| corec_inj : forall (F1 C1 V1 F2 C2 V2:Type)
  (Sem1 : RelyGuaranteeSemantics (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
  (Sem2 : RelyGuaranteeSemantics (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
  (P1 : AST.program F1 V1)
  (P2 : AST.program F2 V2)
  entrypoints jInit
  (Inj_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
    (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs)
      /\ Mem.inject jInit m1 m2))
  (ePts_ok: entryPts_inject_ok P1 P2 jInit ExternIdents entrypoints)
  (preserves_globals: meminj_preserves_globals (Genv.globalenv P1) jInit)
  (R:Forward_simulation_inj.Forward_simulation_inject _ _ Sem1 Sem2 
    (Genv.globalenv P1) (Genv.globalenv P2) entrypoints),
  prog_main P1 = prog_main P2 ->
 (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
  GenvHyp P1 P2 ->
  externvars_ok P1 ExternIdents ->
  I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
  core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2

| corec_trans: forall  (F1 C1 V1 F2 C2 V2 F3 C3 V3:Type)
  (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
  (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
  (Sem3 : CoreSemantics (Genv.t F3 V3) C3 mem (list (ident * globdef F3 V3)))
  (P1 : AST.program F1 V1)
  (P2 : AST.program F2 V2)
  (P3 : AST.program F3 V3),
  core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
  core_correctness I ExternIdents F2 C2 V2 F3 C3 V3 Sem2 Sem3 P2 P3 ->
  core_correctness I ExternIdents F1 C1 V1 F3 C3 V3 Sem1 Sem3 P1 P3.

Lemma corec_I: forall {F1 C1 V1 F2 C2 V2}
  (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
  (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
  (P1 : AST.program F1 V1)
  (P2 : AST.program F2 V2)  ExternIdents I,
  core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
  I _ _ _ Sem1 P1 /\ I _ _ _ Sem2 P2.
Proof. intros. induction X; intuition. Qed.

Lemma corec_main: forall {F1 C1 V1 F2 C2 V2}
  (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
  (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
  (P1 : AST.program F1 V1)
  (P2 : AST.program F2 V2)  ExternIdents I,
  core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
  prog_main P1 = prog_main P2.
Proof. intros. induction X; intuition. congruence. Qed.

(*TRANSITIVITY OF THE GENV-ASSUMPTIONS:*)
Lemma corec_Genv:forall {F1 C1 V1 F2 C2 V2}
  (Sem1 : CoreSemantics (Genv.t F1 V1) C1 mem (list (ident * globdef F1 V1)))
  (Sem2 : CoreSemantics (Genv.t F2 V2) C2 mem (list (ident * globdef F2 V2)))
  (P1 : AST.program F1 V1)
  (P2 : AST.program F2 V2)  ExternIdents I,
  core_correctness I ExternIdents F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2 ->
  GenvHyp P1 P2.
Proof. 
  intros. induction X; intuition. 
  destruct IHX1.
  destruct IHX2.
  split; intros; eauto. rewrite H1. apply H. 
Qed.

Inductive cc_sim (I: forall F C V 
                     (Sem : CoopCoreSem (Genv.t F V) C (list (ident * globdef F V)))
                     (P : AST.program F V),Prop)
(ExternIdents: list (ident * external_description)) entrypoints:
forall (F1 C1 V1 F2 C2 V2:Type)
  (Sem1 : CoopCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
  (Sem2 : CoopCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
  (P1 : AST.program F1 V1)
  (P2 : AST.program F2 V2), Type :=
  ccs_eq : forall  (F1 C1 V1 F2 C2 V2:Type)
    (Sem1 : CoopCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
    (Sem2 : CoopCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
    (P1 : AST.program F1 V1)
    (P2 : AST.program F2 V2)
    (Eq_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
      (exists m2, initial_mem Sem2 (Genv.globalenv P2)  m2 P2.(prog_defs) /\ m1=m2))
    (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
    (R:Forward_simulation_eq.Forward_simulation_equals _ _ _ Sem1 Sem2 
      (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints), 
    prog_main P1 = prog_main P2 -> 
   (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
    GenvHyp P1 P2 ->
    I _ _ _  Sem1 P1 -> I _ _ _  Sem2 P2 -> 
    cc_sim I ExternIdents  entrypoints F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 | ccs_ext : forall  (F1 C1 V1 F2 C2 V2:Type)
   (Sem1 : CoopCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
   (Sem2 : CoopCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
   (P1 : AST.program F1 V1)
   (P2 : AST.program F2 V2)
   (Extends_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs) /\
       Mem.extends m1 m2))
   (ePts_ok: entryPts_ok P1 P2 ExternIdents entrypoints)
   (R:Coop_forward_simulation_ext.Forward_simulation_extends _ _ Sem1 Sem2 
     (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints),
   prog_main P1 = prog_main P2 -> 
  (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
   GenvHyp P1 P2 ->
   I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
               cc_sim I ExternIdents  entrypoints F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2
 | ccs_inj : forall  (F1 C1 V1 F2 C2 V2:Type)
   (Sem1 : CoopCoreSem (Genv.t F1 V1) C1 (list (ident * globdef F1 V1)))
   (Sem2 : CoopCoreSem (Genv.t F2 V2) C2 (list (ident * globdef F2 V2)))
   (P1 : AST.program F1 V1)
   (P2 : AST.program F2 V2)
   jInit
   (Inj_init: forall m1, initial_mem Sem1  (Genv.globalenv P1)  m1 P1.(prog_defs)->
     (exists m2, initial_mem Sem2  (Genv.globalenv P2)  m2 P2.(prog_defs)
       /\ Mem.inject jInit m1 m2))
   (ePts_ok: entryPts_inject_ok P1 P2 jInit ExternIdents entrypoints)
   (preserves_globals: meminj_preserves_globals (Genv.globalenv P1) jInit)
   (R:Coop_forward_simulation_inj.Forward_simulation_inject _ _ Sem1 Sem2 
     (Genv.globalenv P1) (Genv.globalenv P2)  entrypoints),
   prog_main P1 = prog_main P2 ->
   (*HERE IS THE INJECTION OF THE GENV-ASSUMPTIONS INTO THE PROOF:*)
   GenvHyp P1 P2 ->
   externvars_ok P1 ExternIdents ->
   I _ _ _ Sem1 P1 -> I _ _ _ Sem2 P2 -> 
   cc_sim I ExternIdents entrypoints  F1 C1 V1 F2 C2 V2 Sem1 Sem2 P1 P2.

End CompilerCorrectness.