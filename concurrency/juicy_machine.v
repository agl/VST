Require Import compcert.lib.Axioms.

Add LoadPath "../concurrency" as concurrency.

Require Import sepcomp. Import SepComp.
Require Import sepcomp.semantics_lemmas.

Require Import concurrency.pos.
Require Import concurrency.concurrent_machine.
Require Import concurrency.pos.
Require Import Coq.Program.Program.
Require Import ssreflect ssrbool ssrnat ssrfun eqtype seq fintype finfun.
Set Implicit Arguments.

(*NOTE: because of redefinition of [val], these imports must appear 
  after Ssreflect eqtype.*)
Require Import compcert.common.AST.     (*for typ*)
Require Import compcert.common.Values. (*for val*)
Require Import compcert.common.Globalenvs. 
Require Import compcert.common.Memory.
Require Import compcert.lib.Integers.

Require Import Coq.ZArith.ZArith.

(*From msl get the juice! *)
Require Import msl.rmaps.
Require Import veric.compcert_rmaps.
Require Import veric.juicy_mem.
Require Import veric.juicy_extspec.
Require Import veric.jstep.

(**)
Require Import veric.res_predicates. (*For the precondition of lock make and free*)

Notation EXIT := 
  (EF_external "EXIT" (mksignature (AST.Tint::nil) None)). 

Notation CREATE_SIG := (mksignature (AST.Tint::AST.Tint::nil) (Some AST.Tint) cc_default).
Notation CREATE := (EF_external "CREATE" CREATE_SIG).

Notation READ := 
  (EF_external "READ"
               (mksignature (AST.Tint::AST.Tint::AST.Tint::nil) (Some AST.Tint) cc_default)).
Notation WRITE := 
  (EF_external "WRITE"
               (mksignature (AST.Tint::AST.Tint::AST.Tint::nil) (Some AST.Tint) cc_default)).

Notation MKLOCK := 
  (EF_external "MKLOCK" (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default)).
Notation FREE_LOCK := 
  (EF_external "FREE_LOCK" (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default)).

Notation LOCK_SIG := (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default).
Notation LOCK := (EF_external "LOCK" LOCK_SIG).
Notation UNLOCK_SIG := (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default).
Notation UNLOCK := (EF_external "UNLOCK" UNLOCK_SIG).

Definition LKCHUNK:= Mint32.
Definition LKSIZE:= align_chunk LKCHUNK.

Require Import (*compcert_linking*) concurrency.permissions.


Module LockPool.
  Definition LockPool:= address -> option rmap.
End LockPool.
Export LockPool.

Module ThreadPool.
  Section ThreadPool.
    
    Variable cT : Type.
    Notation ctl':= (@ctl cT).
    Record t := mk
                  { num_threads : pos
                    ; pool :> 'I_num_threads -> ctl'
                    ; juice : 'I_num_threads -> rmap;
                    lpool : LockPool
                                                
                  }.
    
  End ThreadPool.
End ThreadPool.


(* There are some overlaping definition conflicting. 
   Here we fix that. But this is obviously ugly and
   the conflicts should be removed by renaming!     *)
  Notation tpool := ThreadPool.t. 
  Notation "x <= y" := (x <= y)%nat. 
  Notation "x < y" := (x < y)%nat.
  Notation Kstop := concurrent_machine.Kstop.

Section poolDefs.

  Variable cT : Type.
  Notation ctl':= (@ctl cT).
  Variable (tp : ThreadPool.t cT).

  Import ThreadPool.

  Notation num_threads := (ThreadPool.num_threads tp).
  Notation thread_pool := (t cT).

  (* Per-thread disjointness definition*)
  Definition race_free tp :=
    forall tid0 tid0' (Htid0 : (tid0 < (@ThreadPool.num_threads cT tp))%nat)
      (Htid0' : tid0' < (@ThreadPool.num_threads cT tp)) (Htid: tid0 <> tid0'),
      joins (juice tp (Ordinal Htid0))
                       (juice tp (Ordinal Htid0')).

  Definition newJuice_wf pmap :=
    forall tid0 (Htid0 : tid0 < num_threads),
      joins ((juice tp) (Ordinal Htid0)) pmap.

  Require Import fintype.

  Lemma unlift_m_inv : forall tid (Htid : tid < num_threads.+1) ord
                         (Hunlift: unlift (ordinal_pos_incr num_threads)
                                          (Ordinal (n:=num_threads.+1) (m:=tid) Htid)
                                   = Some ord),
                         nat_of_ord ord = tid.
  Proof.
    intros.
    assert (Hcontra: unlift_spec (ordinal_pos_incr num_threads)
                                 (Ordinal (n:=num_threads.+1) (m:=tid) Htid) (Some ord)).
    rewrite <- Hunlift.
    apply/unliftP.
    inversion Hcontra; subst.
    inversion H0.
    unfold bump.
    assert (pf: ord < num_threads)
      by (by rewrite ltn_ord).
    assert (H: num_threads <= ord = false).
    rewrite ltnNge in pf.
    rewrite <- Bool.negb_true_iff. auto.
    rewrite H. simpl. rewrite add0n. reflexivity.
  Defined.
  
  Definition addThread (c : cT) (pmap : rmap) : thread_pool :=
    let: new_num_threads := pos_incr num_threads in
    let: new_tid := ordinal_pos_incr num_threads in
    @mk cT new_num_threads
        (fun (n : 'I_new_num_threads) => 
           match unlift new_tid n with
             | None => Kresume c
             | Some n' => tp n'
           end)
        (fun (n : 'I_new_num_threads) => 
           match unlift new_tid n with
             | None => pmap
             | Some n' => (juice tp) n'
           end)
        ((lpool tp)).

  Lemma addThread_racefree :
    forall c p (Hwf: newJuice_wf p) (Hrace: race_free tp),
      race_free (addThread c p).
  Proof.
    unfold race_free in *. intros.
    simpl.
    match goal with
      | [ |- context[ match ?Expr with _ => _ end]] =>
        destruct Expr as [ord0|] eqn:Hget0
    end;
      match goal with
        | [ |- context[ match ?Expr with _ => _ end]] =>
          destruct Expr as [ord1|] eqn:Hget1
      end; simpl in *.
    - apply unlift_m_inv in Hget0.
      apply unlift_m_inv in Hget1. subst.
      destruct ord0 as [tid0 pf0], ord1 as [tid1 pf1]; simpl in Htid.
      eapply Hrace; eauto.
    - apply unlift_m_inv in Hget0.
      subst. unfold newJuice_wf in Hwf.
      destruct ord0. eapply Hwf; eauto.
    - apply unlift_m_inv in Hget1.
      subst. unfold newJuice_wf in Hwf.
      destruct ord1.
      apply joins_comm. eapply Hwf; eauto.
    - destruct (tid0 == num_threads) eqn:Heq0.
      + move/eqP:Heq0=>Heq0. subst.
        assert (Hcontra: (ordinal_pos_incr num_threads) !=
                                                        (Ordinal (n:=num_threads.+1) (m:=tid0') Htid0')).
        { apply/eqP. intros Hcontra.
          unfold ordinal_pos_incr in Hcontra.
          inversion Hcontra; auto.
        }
        exfalso. apply unlift_some in Hcontra. rewrite Hget1 in Hcontra.
        destruct Hcontra. discriminate.
      + move/eqP:Heq0=>Heq0.
        assert (Hcontra: (ordinal_pos_incr num_threads) !=
                                                        (Ordinal (n:=num_threads.+1) (m:=tid0) Htid0)).
        { apply/eqP. intros Hcontra.
          unfold ordinal_pos_incr in Hcontra. inversion Hcontra. subst. auto. }
        exfalso. apply unlift_some in Hcontra. rewrite Hget0 in Hcontra. destruct Hcontra.
        discriminate.
  Defined.
  
  Definition updThreadC' (tid : 'I_num_threads) (c' : cT) : thread_pool :=
    @mk cT num_threads (fun (n : 'I_num_threads) =>
                          if n == tid then Krun c' else tp n) (juice tp)
        (lpool tp).
  Definition containsThread: ThreadPool.t cT -> nat -> Prop:=
    fun ms tid0 => tid0 < (ThreadPool.num_threads ms).
  
  Definition cont2ord {ms tid0} (cnt: containsThread ms tid0) :=
    Ordinal cnt.
  Definition updThreadC { tid0}(cnt: containsThread tp tid0) (c' : ctl) : tpool cT :=
    @mk cT num_threads
        (fun n => if n == (cont2ord cnt) then c' else (pool tp)  n)
        (juice tp)
        (lpool tp).
  Definition updThreadP (tid : 'I_num_threads) (pmap' : rmap) : thread_pool :=
    @mk cT num_threads (pool tp) (fun (n : 'I_num_threads) =>
                                    if n == tid then pmap' else (juice tp) n)
        (lpool tp).

  Definition permMap_wf pmap tid :=
    forall tid0 (Htid0 : tid0 < num_threads) (Hneq: tid <> tid0),
      joins ((juice tp) (Ordinal Htid0)) pmap.
  
  Definition updThread (tid : 'I_num_threads) (c' : ctl)
             (pmap : rmap): thread_pool :=
    @mk cT num_threads
        (fun (tid' : 'I_num_threads) =>
           if tid' == tid then c' else tp tid')
        (fun (tid' : 'I_num_threads) =>
           if tid' == tid then pmap else (juice tp) tid') 
         (lpool tp).

  Lemma updThread_wf : forall tid (pf : tid < num_threads) pmap
                         (Hwf: permMap_wf pmap tid)
                         c'
                         (Hrace_free: race_free tp),
                         race_free (updThread (Ordinal pf) c' pmap).
  Proof.
    intros.
    unfold race_free. intros.
    simpl.
    destruct (Ordinal (n:=num_threads) (m:=tid0) Htid0 ==  Ordinal (n:=num_threads) (m:=tid) pf) eqn:Heq0,
                                                                                                     (Ordinal (n:=num_threads) (m:=tid0') Htid0' == Ordinal (n:=num_threads) (m:=tid) pf) eqn:Heq0'.
    - move/eqP:Heq0 => Heq0. subst.
      move/eqP:Heq0' => Heq0'. inversion Heq0'. inversion Heq0; subst. exfalso; auto.
    - move/eqP:Heq0=>Heq0; inversion Heq0; subst. 
      apply joins_comm.
      eapply Hwf. simpl; auto.      
    - move/eqP:Heq0'=>Heq0'. inversion Heq0'. subst.
      eapply Hwf. simpl; auto.
    - simpl in *. eapply Hrace_free; eauto.
  Defined.

  
  

  Definition getThreadC {ms tid0} (cnt: containsThread ms tid0) : ctl :=
    (pool ms) (cont2ord cnt).
  
  Definition getThreadPerm (tid : 'I_num_threads) : rmap := (juice tp) tid.

  Import Maps.

  Record mem_cohere' m phi :=
    { cont_coh: contents_cohere m phi;
      acc_coh: access_cohere m phi;
      max_coh: max_access_cohere m phi;
      all_coh: alloc_cohere m phi
    }.
  Definition mem_cohere m:=
    forall tid, mem_cohere' m (getThreadPerm tid). 
      
  Record mem_compatible m :=
    { perm_comp: mem_cohere m
      (* ; mem_canonical: isCanonical (getMaxPerm m) *)
    }.

End poolDefs.

Arguments updThread {_} tp tid c' pmap.
Arguments addThread {_} tp c pmap.

Section poolLemmas.

  Context {cT : Type} (tp : ThreadPool.t cT).

  Import ThreadPool.
(*
  Lemma gssThreadCode tid c' p' :
    forall (cnt : containsThread (updThread tp (cont2ord cnt) c' p') tid),
    getThreadC  ctn = c'.
  Proof. by rewrite /getThreadC /updThread /= eq_refl. Defined.

  Lemma gsoThread (tid tid' : 'I_(num_threads tp)) c' p':
    tid' != tid -> getThreadC (updThread tp tid c' p') tid' = getThreadC tp tid'.
  Proof. by rewrite /getThreadC /updThread /=; case Heq: (tid' == tid). Defined.

  Lemma gssThreadPerm (tid : 'I_(num_threads tp)) c' p' : 
    getThreadPerm (updThread tp tid c' p') tid = p'.
  Proof. by rewrite /getThreadC /updThread /= eq_refl. Defined.

  Lemma gsoThreadPerm (tid tid' : 'I_(num_threads tp)) c' p':
    tid' != tid -> getThreadPerm (updThread tp tid c' p') tid' = getThreadPerm tp tid'.
  Proof. by rewrite /getThreadPerm /updThread /=; case Heq: (tid' == tid). Defined.

  Lemma getAddThread c pmap tid :
    tid = ordinal_pos_incr (num_threads tp) ->
    getThreadC (addThread tp c pmap) tid = c.
  Proof. by rewrite /getThreadC /addThread /= => <-; rewrite unlift_none. Qed.
*)
(*
  Lemma permMapsInv_lt : forall m (Hinv: mem_compatible tp m) tid,
                           permMapLt (getThreadPerm tp tid) p.
  Proof.
    intros. 
    unfold permMapLt; auto.
  Qed.*)

  Definition restrPermMap p' m (Hlt: permMapLt p' (getMaxPerm m)) : mem.
  Proof.
    refine ({|
               Mem.mem_contents := Mem.mem_contents m;
               Mem.mem_access :=
                 (fun ofs k =>
                    match k with
                      | Cur => None
                      | Max => fst (Mem.mem_access m) ofs k
                    end, Maps.PTree.map (fun b f =>
                                           fun ofs k =>
                                             match k with
                                               | Cur =>
                                                 (Maps.PMap.get b p') ofs
                                               | Max =>
                                                 f ofs Max
                                             end) (Mem.mem_access m).2);
               Mem.nextblock := Mem.nextblock m;
               Mem.access_max := _;
               Mem.nextblock_noaccess := _;
               Mem.contents_default := Mem.contents_default m |}).
    - unfold permMapLt in Hlt.
      assert (Heq: forall b ofs, Maps.PMap.get b (getMaxPerm m) ofs =
                            Maps.PMap.get b (Mem.mem_access m) ofs Max).
      { unfold getMaxPerm. intros.
        rewrite Maps.PMap.gmap. reflexivity. }
      intros.
      specialize (Hlt b ofs).
      specialize (Heq b ofs).
      unfold getMaxPerm in Hlt.
      unfold Maps.PMap.get in *. simpl in *.
      rewrite Maps.PTree.gmap; simpl.
      match goal with
        | [|- context[match Coqlib.option_map ?Expr1 ?Expr2  with _ => _ end]] =>
          destruct (Coqlib.option_map Expr1 Expr2) as [f|] eqn:?
      end; auto; unfold Coqlib.option_map in Heqo.
      destruct (Maps.PTree.get b (Mem.mem_access m).2) eqn:?; try discriminate.
      + inversion Heqo; subst; clear Heqo.
        rewrite Heq in Hlt. auto.
      + unfold Mem.perm_order''. by destruct ((Mem.mem_access m).1 ofs Max).
    - intros b ofs k Hnext.
    - unfold permMapLt in Hlt.
      assert (Heq: forall b ofs, Maps.PMap.get b (getMaxPerm m) ofs =
                            Maps.PMap.get b (Mem.mem_access m) ofs Max).
      { unfold getMaxPerm. intros.
        rewrite Maps.PMap.gmap. reflexivity. }
      specialize (Hlt b ofs).
      specialize (Heq b ofs).
      unfold Maps.PMap.get in *.
      simpl in *.
      rewrite Maps.PTree.gmap; simpl.
      assert (H := Mem.nextblock_noaccess m).
      specialize (H b). unfold Maps.PMap.get in H.
      match goal with
        | [|- context[match Coqlib.option_map ?Expr1 ?Expr2  with _ => _ end]] =>
          destruct (Coqlib.option_map Expr1 Expr2) as [f|] eqn:?
      end; auto; unfold Coqlib.option_map in Heqo;
      destruct (Maps.PTree.get b (Mem.mem_access m).2) eqn:Heqo2; try discriminate.
      inversion Heqo. subst f. clear Heqo.
      destruct k; auto.
      rewrite Heq in Hlt.
      specialize (H ofs Max). rewrite H in Hlt; auto.
      unfold Mem.perm_order'' in Hlt. destruct (Maps.PTree.get b p'.2).
      destruct (o0 ofs); tauto.
      destruct (p'.1 ofs); tauto.
      rewrite H; auto. destruct k; auto.
  Defined. 
  
  Lemma restrPermMap_nextblock :
    forall p' m (Hlt: permMapLt p' (getMaxPerm m)),
      Mem.nextblock (restrPermMap Hlt) = Mem.nextblock m.
  Proof.
    intros. unfold restrPermMap. reflexivity.
  Qed.

  Lemma restrPermMap_irr : forall p' p'' m
                             (Hlt : permMapLt p' (getMaxPerm m))
                             (Hlt': permMapLt p'' (getMaxPerm m))
                             (Heq_new: p' = p''),
                             restrPermMap Hlt = restrPermMap Hlt'.
  Proof.
    intros. subst.
    apply f_equal. by apply proof_irr.
  Qed.

  (*
  Lemma restrPermMap_disjoint_inv:
    forall (mi mj m : mem) (pi pj : rmap)
      (Hcan_m: isCanonical (getMaxPerm m))
      (Hltj: permMapLt pj (getMaxPerm m))
      (Hlti: permMapLt pi (getMaxPerm m))
      (Hdisjoint: permMapsDisjoint pi pj)
      (Hrestrj: restrPermMap Hltj = mj)
      (Hrestri: restrPermMap Hlti = mi),
      permMapsDisjoint (getCurPerm mi) (getCurPerm mj).
  Proof.
    intros. rewrite <- Hrestri. rewrite <- Hrestrj.
    unfold restrPermMap, getCurPerm, permMapsDisjoint. simpl in *.
    intros b ofs.
    do 2 rewrite Maps.PMap.gmap.
    clear Hrestrj Hrestri.
    unfold permMapLt, Mem.perm_order'' in *.
    specialize (Hltj b ofs); specialize (Hlti b ofs).
    unfold getMaxPerm in *; simpl in *.
    rewrite Maps.PMap.gmap in Hlti, Hltj.
    unfold permMapsDisjoint, Maps.PMap.get in *; simpl in *.
    do 2 rewrite Maps.PTree.gmap. unfold Coqlib.option_map.
    specialize (Hdisjoint b ofs).
    assert (Hnone: (Mem.mem_access m).1 ofs Max = None)
      by (unfold isCanonical in Hcan_m; simpl in Hcan_m;
            by apply equal_f with (x:=ofs) in Hcan_m).
    destruct (Maps.PTree.get b (Mem.mem_access m).2) eqn:?; auto.
    rewrite Hnone in Hlti, Hltj;
      destruct (Maps.PTree.get b pi.2)
      as [f1 |] eqn:?;
                destruct (Maps.PTree.get b pj.2) as [f2|] eqn:?;
      repeat match goal with
               | [H: match ?Expr with _ => _ end |- _] => destruct Expr
             end; tauto.
  Qed.*)
  
  Lemma no_race_wf : forall tid (pf: tid < (num_threads tp)) (Hrace: race_free tp),
                       permMap_wf tp (getThreadPerm tp (Ordinal pf)) tid.
  Proof.
    intros. unfold permMap_wf; auto.
  Defined.

End poolLemmas.

Module JMem.
  
  Parameter get_fun_spec: juicy_mem -> address -> val -> option (pred rmap * pred rmap).
  Parameter get_lock_inv: juicy_mem -> address -> option (pred rmap).
  
End JMem.

Module Concur.
  Section Concur.
    
    Import ThreadPool.
    Context {cT G : Type} {the_sem : CoreSemantics G cT mem}{LP:LockPool}.
    
    Notation cT' := (@ctl cT).
    Notation thread_pool := (t cT).
    Notation perm_map := rmap.

    Definition containsThread: ThreadPool.t cT -> nat -> Prop:=
      fun ms tid0 => tid0 < (ThreadPool.num_threads ms).

    Variable the_ge : G.
    
    Record invariant tp :=
      { (*canonical : forall tid, isCanonical (juice tp tid);*)
        no_race : race_free tp;
        lock_pool : forall (cnt : containsThread tp 0), exists c,
                      getThreadC cnt  = Krun c /\ halted the_sem c
      }.
    
    (* Semantics of the coarse-grained concurrent machine*)
    

    Definition personal_mem {tid0 tp m} (cnt: containsThread tp tid0)
               (Hcompatible: mem_compatible tp m): juicy_mem.
    pose (tid := cont2ord cnt). 
    destruct Hcompatible as [perm_comp  mem_canon].
    destruct (perm_comp tid).                                                 
    apply (mkJuicyMem m (getThreadPerm tp tid)); auto.
    Defined.

    Definition juicy_sem:= (FSem.F _ _ JuicyFSem.t) _ _ the_sem.
    
    Inductive juicy_step {tid0 tp m} (cnt: containsThread tp tid0)
      (Hcompatible: mem_compatible tp m) : thread_pool -> mem  -> Prop :=
    | step_juicy :
        forall (tp':thread_pool) c jm jm' m' (c' : cT),
          let: lp := lpool tp in
          let: tid := cont2ord cnt in
          forall (Hpersonal_perm:
               personal_mem cnt Hcompatible = jm)
            (Hinv : invariant tp)
            (Hthread: getThreadC cnt = Krun c)
            (Hcorestep: corestep juicy_sem the_ge c jm c' jm')
            (Htp': tp' = @updThread cT tp tid (Krun c') (m_phi jm'))
            (Hm': m_dry jm' = m' ),
            juicy_step cnt Hcompatible tp' m'.

    Definition pack_res_inv R:= SomeP ([unit:Type])  (fun _ => R) .
    
    Inductive conc_step {tid0 tp m}
              (cnt0:containsThread tp tid0)(Hcompat:mem_compatible tp m):
      thread_pool -> mem -> Prop :=
    | step_lock :
        forall (tp':thread_pool) jm c c' jm' b ofs d_phi,
          let: tid := cont2ord cnt0 in
          let: phi := m_phi jm in
          let: phi' := m_phi jm' in
          let: m' := m_dry jm' in
          forall
            (Hinv : invariant tp)
            (Hthread: getThreadC cnt0 = Kstop c)
            (Hat_external: at_external the_sem c =
                           Some (LOCK, ef_sig LOCK, Vptr b ofs::nil))
            (Hcompatible: mem_compatible tp m)
            (Hpersonal_perm: 
               personal_mem cnt0 Hcompatible = jm)
            (sh:Share.t)(R:pred rmap)
            (HJcanwrite: phi@(b, Int.intval ofs) = YES sh pfullshare (LK LKSIZE) (pack_res_inv R))
            (Hload: Mem.load Mint32 m b (Int.intval ofs) = Some (Vint Int.one))
            (Hstore: Mem.store Mint32 m b (Int.intval ofs) (Vint Int.zero) = Some m')
            (Hat_external: after_external the_sem (Some (Vint Int.zero)) c = Some c')
            (His_unlocked:lpool tp (b, Int.intval ofs) = Some d_phi )
            (Hadd_lock_res: join (m_phi jm) d_phi  phi')  
            (Htp': tp' = updThread tp tid (Kresume c') phi'),
            conc_step cnt0 Hcompat tp' m'                 
    | step_unlock :
        forall  (tp':thread_pool) jm c c' jm' b ofs (d_phi phi':rmap) (R: pred rmap) ,
          let: tid := cont2ord cnt0 in
          let: phi := m_phi jm in
          let: phi' := m_phi jm' in
          let: m' := m_dry jm' in
          forall
            (Hinv : invariant tp)
            (Hthread: getThreadC cnt0 = Kstop c)
            (Hat_external: at_external the_sem c =
                           Some (UNLOCK, ef_sig UNLOCK, Vptr b ofs::nil))
            (Hcompatible: mem_compatible tp m)
            (Hpersonal_perm: 
               personal_mem cnt0 Hcompatible = jm)
            (sh:Share.t)(R:pred rmap)
            (HJcanwrite: phi@(b, Int.intval ofs) = YES sh pfullshare (LK LKSIZE) (pack_res_inv R))
            (Hload: Mem.load Mint32 m b (Int.intval ofs) = Some (Vint Int.zero))
            (Hstore: Mem.store Mint32 m b (Int.intval ofs) (Vint Int.one) = Some m')
            (* what does the return value denote?*)
            (Hat_external: after_external the_sem (Some (Vint Int.zero)) c = Some c')
            (Hget_lock_inv: JMem.get_lock_inv jm (b, Int.intval ofs) = Some R)
            (Hsat_lock_inv: R d_phi)
            (Hrem_lock_res: join d_phi phi' (m_phi jm))
            (Htp': tp' = updThread tp tid (Kresume c') phi'),
            conc_step cnt0 Hcompat tp' m'          
    | step_create :
        (* HAVE TO REVIEW THIS STEP LOOKING INTO THE ORACULAR SEMANTICS*)
        forall  (tp_upd tp':thread_pool) c c' c_new vf arg jm (d_phi phi': rmap) b ofs P Q,
          let: tid := cont2ord cnt0 in
          forall
            (Hinv : invariant tp)
            (Hthread: getThreadC cnt0 = Kstop c)
            (Hat_external: at_external the_sem c =
                           Some (CREATE, ef_sig CREATE, vf::arg::nil))
            (Hinitial: initial_core the_sem the_ge vf (arg::nil) = Some c_new)
            (Hfun_sepc: vf = Vptr b ofs)
            (Hafter_external: after_external the_sem
                                             (Some (Vint Int.zero)) c = Some c')
            (Hcompatible: mem_compatible tp m)
            (Hpersonal_perm: 
               personal_mem cnt0 Hcompatible = jm)
            (Hget_fun_spec: JMem.get_fun_spec jm (b, Int.intval ofs) arg = Some (P,Q))
            (Hsat_fun_spec: P d_phi)
            (Hrem_fun_res: join d_phi phi' (m_phi jm))
            (Htp': tp_upd = updThread tp tid (Kresume c') phi')
            (Htp': tp' = addThread tp_upd c_new d_phi),
            conc_step cnt0 Hcompat tp' m
                     
    | step_mklock :
        forall  (tp' tp'': thread_pool) jm jm' c c' b ofs R ,
          let: tid := cont2ord cnt0 in
          let: phi := m_phi jm in
          let: phi' := m_phi jm' in
          let: m' := m_dry jm' in
          forall
            (Hinv : invariant tp)
            (Hthread: getThreadC cnt0 = Kstop c)
            (Hat_external: at_external the_sem c =
                           Some (MKLOCK, ef_sig MKLOCK, Vptr b ofs::nil))
            (Hcompatible: mem_compatible tp m)
            (Hpersonal_perm: 
               personal_mem cnt0 Hcompatible = jm)
            (*This the first share of the lock, 
              can/should this be different for each location? *)
            (sh:Share.t)
            (*Check I have the right permission to mklock and the riht value (i.e. 0) *)
            (Haccess: address_mapsto LKCHUNK (Vint Int.zero) sh Share.top (b, Int.intval ofs) phi)
            (*Check the new memory has the lock*)
            (Hlock: phi'@ (b, Int.intval ofs) = YES sh pfullshare (LK LKSIZE) (pack_res_inv R))
            (*Check the new memory has the right continuations THIS IS REDUNDANT! *)
            (*Hcont: forall i, 0<i<LKSIZE ->   phi'@ (b, Int.intval ofs + i) = YES sh pfullshare (CT i) NoneP*)
            (*Check the two memories coincide in everything else *)
            (Hj_forward: forall loc, loc#1 <> b \/ ~0<loc#2-(Int.size ofs)<LKSIZE  -> phi@loc = phi'@loc)
            (*Check the memories are equal!*)
            (Hm_forward: m = m')
            (Hat_external: after_external
                             the_sem (Some (Vint Int.zero)) c = Some c')
            (Htp': tp' = updThread tp tid (Kresume c') phi'),
            conc_step cnt0 Hcompat tp'' m' 
    | step_freelock :
        forall  (tp' tp'': thread_pool) c c' b ofs jm jm' R,
          let: tid := cont2ord cnt0 in
          let: phi := m_phi jm in
          let: phi' := m_phi jm' in
          let: m' := m_dry jm' in
          forall
            (Hinv : invariant tp)
            (Hthread: getThreadC cnt0 = Kstop c)
            (Hat_external: at_external the_sem c =
                           Some (FREE_LOCK, ef_sig FREE_LOCK, Vptr b ofs::nil))
            (Hcompatible: mem_compatible tp m)
            (Hpersonal_perm: 
               personal_mem cnt0 Hcompatible = jm)
            (*This the first share of the lock, 
              can/should this be different for each location? *)
            (sh:Share.t)
            (*Check the new memoryI have has the right permission to mklock and the riht value (i.e. 0) *)
            (Haccess: address_mapsto LKCHUNK (Vint Int.zero) sh Share.top (b, Int.intval ofs) phi')
            (*Check the old memory has the lock*)
            (Hlock: phi@ (b, Int.intval ofs) = YES sh pfullshare (LK LKSIZE) (pack_res_inv R))
            (*Check the old memory has the right continuations  THIS IS REDUNDANT!*)
            (*Hcont: forall i, 0<i<LKSIZE ->   phi@ (b, Int.intval ofs + i) = YES sh pfullshare (CT i) NoneP *)
            (*Check the two memories coincide in everything else *)
            (Hj_forward: forall loc, loc#1 <> b \/ ~0<loc#2-(Int.size ofs)<LKSIZE  -> phi@loc = phi'@loc)
            (*Check the memories are equal!*)
            (Hm_forward: m = m')
            (Hat_external: after_external the_sem (Some (Vint Int.zero)) c = Some c')
            (Htp': tp' = updThread tp tid (Kresume c') (m_phi jm')),
            conc_step cnt0 Hcompat  tp'' (m_dry jm')  (* m_dry jm' = m_dry jm = m *)
                     
    | step_lockfail :
        forall  c b ofs jm,
          let: tid := cont2ord cnt0 in
          let: phi := m_phi jm in
          forall
            (Hinv : invariant tp)
            (Hthread: getThreadC cnt0 = Kstop c)
            (Hat_external: at_external the_sem c =
                           Some (LOCK, ef_sig LOCK, Vptr b ofs::nil))
            (Hcompatible: mem_compatible tp m)
            (Hpersonal_perm: 
               personal_mem cnt0 Hcompatible = jm)
            (sh:Share.t)(R:pred rmap)
            (HJcanwrite: phi@(b, Int.intval ofs) = YES sh pfullshare (LK LKSIZE) (pack_res_inv R))
            (Hload: Mem.load Mint32 m b (Int.intval ofs) = Some (Vint Int.zero)),
            conc_step cnt0 Hcompat tp m.
  End Concur.
  
  Module JuicyMachineSig (Sem: Semantics) <: ConcurrentMachineSig NatTID.
                                                   
    (*TID = NAT*)
    Definition tid := nat.                                             
    (*Memories*)
    Parameter level: nat.
    Definition richMem: Type:= juicy_mem.
    Definition dryMem: richMem -> mem:= m_dry.
    
    (*CODE*)
    Definition cT: Type:= Sem.C.
    Definition G: Type:= Sem.G.
    Definition Sem := Sem.Sem.
    Definition cT': Type := @ctl cT.
    
    (*thread pool*)
    Import ThreadPool.  
    Notation thread_pool := (t cT).  
    
    (*MACHINE VARIABLES*)
    Definition machine_state: Type:= thread_pool.
    Definition containsThread: machine_state -> tid -> Prop:= containsThread.
    Definition lp_id : tid:= (0)%nat. (*lock pool thread id*)
    
    (*INVARIANTS*)
    (*The state respects the memory*)
    Definition mem_compatible: machine_state -> mem -> Prop:=
      @mem_compatible cT.
    
    (*CODE GETTER AND SETTER*)
    Definition getThreadC: forall {ms tid0}, containsThread ms tid0 -> @ctl cT:= @getThreadC cT.                  
    Definition updThreadC: forall {ms tid0}, containsThread ms tid0 -> @ctl cT -> machine_state:= @updThreadC cT.
    
    (*Steps*)
    Definition cstep (genv:G): forall {tid0 ms m},
                                 containsThread ms tid0 -> mem_compatible ms m ->
                                 machine_state -> mem -> Prop:=
      @juicy_step cT G Sem genv.
    
    
    Definition conc_call (genv:G):
      forall {tid0 ms m}, containsThread ms tid0 -> mem_compatible ms m ->
        machine_state -> mem -> Prop:=
      fun tid ms m => @conc_step cT G Sem genv tid ms m.
    
    Inductive threadHalted': forall {tid0 ms},
                               containsThread ms tid0 -> Prop:=
    | thread_halted':
        forall tp c tid0
          (cnt: containsThread tp tid0),
          let: tid := cont2ord cnt in
          forall
            (Hthread: getThreadC cnt = Krun c)
            (Hcant: halted Sem c),
            threadHalted' cnt. 
    Definition threadHalted: forall {tid0 ms},
                               containsThread ms tid0 -> Prop:= @threadHalted'.


    (* The initial machine has to be redefined.
       Right now its build by default with empty maps,
       but it should be built with the correct juice,
       corresponding to global variables, arguments
       and function specs. *)
    Lemma onePos: (0<1)%coq_nat. auto. Qed.
    Definition initial_machine c:=
      @mk cT (mkPos onePos) (fun _ => c) (fun _ => empty_rmap level) (fun _ => None).
    Definition init_mach (genv:G)(v:val)(args:list val):option machine_state:=
      match initial_core Sem genv v args with
      | Some c => Some (initial_machine (Kresume c))
      | None => None
      end.
      
End JuicyMachineSig.

  (* Here I make the core semantics*)
  Variable example_G: Type.
  Variable example_C: Type.
  Variable example_sem: CoreSemantics example_G example_C mem.
  Module Sem: Semantics.
    Definition G:= example_G.
    Definition C:= example_C.
    Definition M:= mem.
    Definition Sem:=example_sem.
  End Sem.
  Module mySchedule := ListScheduler NatTID.
  Module mySem := JuicyMachineSig Sem.
  Module myCoarseSemantics :=
    CoarseMachine NatTID mySchedule mySem.
  Definition coarse_semantics:=
    myCoarseSemantics.MachineSemantics.
  
End Concur.
