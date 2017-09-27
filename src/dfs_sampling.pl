%%
% Copyright 2017 Harm Brouwer <me@hbrouwer.eu>
%                Noortje Venhuizen <njvenhuizen@gmail.com>
%
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
%
%     http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
%%

:- module(dfs_sampling,
        [
                dfs_sample_models/2,
                dfs_sample_model/1
        ]).

:- use_module(dfs_interpretation).

% dfs_sample_models(+NumModels,-ModelSet)

dfs_sample_models(N,MS) :-
        dfs_sample_models_(N,0,MS).

dfs_sample_models_(N,N,[]) :- !.
dfs_sample_models_(N,I,[M|MS]) :-
        I0 is I + 1,
        dfs_sample_model(M),
        dfs_pprint_model(M),
        dfs_sample_models_(N,I0,MS).

% dfs_sample_model(-Model)

dfs_sample_model((Um,Vm)) :-
        constants_and_universe(Cs,Um),
        dfs_vector_space:ifunc_inst_constants(Cs,Um,VmCs),
        findall(P,user:property(P),Ps),
        dfs_init_g((Um,_),G),
        dfs_sample_properties(Ps,Um,G,VmCs,Vm), !.
dfs_sample_model((Um,Vm)) :-
        dfs_sample_model((Um,Vm)).

% constants_and_universe(-Constants,-Entities)

constants_and_universe(Cs,Um) :-
        findall(C,user:constant(C),Cs),
        length(Cs,N),
        dfs_entities(N,Um).

%% dfs_sample_properties(+Properties,+Universe,+G,IFuncConstants,-IFunc)
%
%  Samples property instantiations using a non-deterministic, probabilistic
%  and incremental inference-driven sampling algorithm. 
%
%  The aim is to arrive at an interpretation function that satisfies a set 
%  of imposed probabilistic and hard constraints. To this end, we start out
%  with with an empty interpretation function, to which we will incrementally
%  add properties. We call this interpretation function the Light World (LVm),
%  and this function will contain all properties that are true in the model.
%  In parallel to the Light World, we will also construct a Dark World (DVm)
%  function that will contain all properties that are false in the model. 
%
%  Given LVm and DVm, a set of randomly ordered properties P, and a set of 
%  constraints C, we then do the following for each property p:
%
%  (1) Add p to LVm, yielding LVm';
%
%  (2) LT = true iff for each constraint c:
%       
%       -- c is satisfied by LVm';
%       -- or if the complement of c is not satisfied by DVm.
%
%  (3) Add p to DVm, yielding DVm';
% 
%  (4) DT = true iff for each constraint c:
%       
%       -- c is satisfied by LVm;
%       -- or if the complement of c is not satisfied by DVm'.
%   
%  (5) Depending on the outcome of (2) and (4):
%
%       -- LT & DT: Infer p with Pr(p): LVm = LVm', otherwise: DVm = DVm'
%       -- LT & !DT: Infer p to be true in the Light World: LVm = LVm'
%       -- !LT & DT: Infer p to be true in the Dark World: DVm = DVm'
%       -- !LT & !DT: The model is inconsistent, and needs to be discarded.
%
%  (6) Repeat (1) for next p. If each p is a property in either LVm or DVm,
%      and LVm satisfies all constraints, LVm is the final interpretation 
%      function.

dfs_sample_properties(Ps,Um,G,VmCs,Vm) :-
        findall(C,user:constraint(C),Cs),
        %findall(C,(user:constraint(C0),optimize_q_forall(C0,C)),Cs),
        random_permutation(Ps,Ps1),
        Ps1 = Ps,
        write(VmCs), nl,
        dfs_constant_instantiations((_,VmCs),CIs),
        dfs_sample_properties_(Ps1,Um,G,CIs,Cs,VmCs,VmCs,Vm).

dfs_sample_properties_([],Um,G,_,Cs,Vm,_,Vm) :- 
        dfs_interpret(Cs,(Um,Vm),G), !.
dfs_sample_properties_([P|Ps],Um,G,CIs,Cs,LVm0,DVm0,LVm) :-
        P =.. [Prop|Args],
        dfs_terms_to_entities(Args,CIs,Es),
        add_property(LVm0,Prop,Es,LVm1),
        ( satisfies_constraints(Cs,(Um,LVm1),(Um,DVm0),G) -> LT = 1 ; LT = 0 ),     %% light world
        add_property(DVm0,Prop,Es,DVm1),
        ( satisfies_constraints(Cs,(Um,LVm0),(Um,DVm1),G) -> DT = 1 ; DT = 0 ),     %% dark world
        (  LT == 1, DT == 1             %% undecided
        -> probability(P,LVm0,Pr), !,
           (  maybe(Pr)
           -> dfs_sample_properties_(Ps,Um,G,CIs,Cs,LVm1,DVm0,LVm)
           ;  dfs_sample_properties_(Ps,Um,G,CIs,Cs,LVm0,DVm1,LVm) )
        ;  (  LT == 1, DT == 0          %% light world
           -> dfs_sample_properties_(Ps,Um,G,CIs,Cs,LVm1,DVm0,LVm)
           ;  (  LT == 0, DT == 1       %% dark world
              -> dfs_sample_properties_(Ps,Um,G,CIs,Cs,LVm0,DVm1,LVm)
              ;  false ) ) ).           %% inconsistent

%% add_property(+IFunc,+Property,+Entities,-IFunc)
%
%  Adds a property for a set of entities to an interpretation function.

add_property([],Prop,[E|Es],[P1]) :-
        !,
        (  Es == []
        -> P1 =.. [Prop|[[E]]]          %% unary predicates
        ;  P1 =.. [Prop|[[[E|Es]]]] ).  %% n-ary predicates
add_property([P0|P0s],Prop,[E|Es],[P1|P0s]) :-
        P0 =.. [Prop|_], !,
        (  Es == []
        -> P0 =.. [Prop|[Es0]],         %% unary predicates
           P1 =.. [Prop|[[E|Es0]]]      
        ;  P0 =.. [Prop|[Es0]],         %% n-ary predicates
           P1 =.. [Prop|[[[E|Es]|Es0]]] ).
add_property([P0|P0s],Prop,Es,[P0|P1s]) :-
        add_property(P0s,Prop,Es,P1s).

%% satisfies_constraints(+Constraints,+LightModel,+DarkModel,+G)
%
%  Returns true when each constraint is either satisfied in the light world,
%  or when its complement is not satisfied in the dark world.

satisfies_constraints([],_,_,_) :- !, true.
satisfies_constraints([C|Cs],LM,DM,G) :-
        dfs_interpret(C,LM,G), !,
        satisfies_constraints(Cs,LM,DM,G).
satisfies_constraints([C|Cs],LM,DM,G) :-
        complement(C,Cc),
        \+ dfs_interpret(Cc,DM,G),
        satisfies_constraints(Cs,LM,DM,G).

%% complement(?Formula,?ComplementFormula)
%
%  Complement of truth/falsehood conditions.

complement(neg(P0),neg(P1)) :-
        !, % !P => !P
        complement(P0,P1).
complement(and(P0,Q0),or(P1,Q1)) :-
        !, % P & Q => P | Q
        complement(P0,P1),
        complement(Q0,Q1).
complement(or(P0,Q0),and(P1,Q1)) :-
        !, % P | Q => P & Q
        complement(P0,P1),
        complement(Q0,Q1).
complement(xor(P0,Q0),or(and(P1,Q1),and(neg(P1,neg(Q1))))) :-
        !, % P (+) Q => (P & Q) | (!P & !Q)
        complement(P0,P1),
        complement(Q0,Q1). 
complement(imp(P0,Q0),and(neg(P1),Q1)) :-
        !, % P -> Q => !P & Q
        complement(P0,P1),
        complement(Q0,Q1).
complement(iff(P0,Q0),or(and(neg(P1),Q1),and(P1,neq(Q1)))) :-
        !, % P <-> Q => (!P & Q) | (P & !Q)
        complement(P0,P1),
        complement(Q0,Q1).
complement(exists(X,P0),forall(X,P1)) :-
        !, % ∃x P => ∀x P
        complement(P0,P1).
complement(forall(X,P0),exists(X,P1)) :-
        !, % ∀x P => ∃x P
        complement(P0,P1).
complement(P,P).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% forall optimization %%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

optimize_q_forall(P,FIs) :-
        q_forall_var_insts(P,VIs),
        findall(FI,q_forall_inst(P,VIs,FI),FIs).

q_forall_inst(neg(P0),VIs,neg(P1)) :-
        !,
        q_forall_inst(P0,VIs,P1).
q_forall_inst(and(P0,Q0),VIs,and(P1,Q1)) :-
        !,
        q_forall_inst(P0,VIs,P1),
        q_forall_inst(Q0,VIs,Q1).
q_forall_inst(or(P0,Q0),VIs,or(P1,Q1)) :-
        !,
        q_forall_inst(P0,VIs,P1),
        q_forall_inst(Q0,VIs,Q1).
q_forall_inst(xor(P0,Q0),VIs,xor(P1,Q1)) :-
        !,
        q_forall_inst(P0,VIs,P1),
        q_forall_inst(Q0,VIs,Q1).
q_forall_inst(imp(P0,Q0),VIs,imp(P1,Q1)) :-
        !,
        q_forall_inst(P0,VIs,P1),
        q_forall_inst(Q0,VIs,Q1).
q_forall_inst(iff(P0,Q0),VIs,iff(P1,Q1)) :-
        !,
        q_forall_inst(P0,VIs,P1),
        q_forall_inst(Q0,VIs,Q1).
q_forall_inst(exists(X,P0),VIs,exists(X,P1)) :-
        !,
        q_forall_inst(P0,VIs,P1).
q_forall_inst(forall(X,imp(P0,Q0)),VIs,imp(P1,Q1)) :-
        !,
        select_var_inst(X,VIs,VIs0),
        q_forall_inst(P0,VIs0,P1),
        q_forall_inst(Q0,VIs0,Q1).
q_forall_inst(forall(X,P0),VIs,forall(X,P1)) :-
        !,
        q_forall_inst(P0,VIs,P1).
q_forall_inst(P,VIs,PI) :-
        prop_inst(P,VIs,PI).

select_var_inst(_,[],[]) :- !.
select_var_inst(X,VIs,[X=E|VIs1]) :-
        findall(X=E,member(X=E,VIs),VIs0),
        findall(Y=E,(member(Y=E,VIs),Y\=X),VIs1),
        select(X=E,VIs0,_).

prop_inst(P,VIs,PI) :-
        P =.. [Prop|As],
        prop_inst_(As,VIs,IAs),
        PI =.. [Prop|IAs].

prop_inst_([],_,[]) :- !.
prop_inst_([A|As],VIs,[X|IAs]) :-
        memberchk(A=X,VIs), !,
        prop_inst_(As,VIs,IAs).
prop_inst_([A|As],VIs,[A|IAs]) :-
        prop_inst_(As,VIs,IAs).

q_forall_var_insts(P,VIs) :-
        q_forall_var_insts_(P,[],VIs0),
        list_to_ord_set(VIs0,VIs).

q_forall_var_insts_(neg(P),Vs,VIs) :-
        !,
        q_forall_var_insts_(P,Vs,VIs).
q_forall_var_insts_(and(P,Q),Vs,VIs) :-
        !,
        q_forall_var_insts_(P,Vs,VIsP),
        q_forall_var_insts_(Q,Vs,VIsQ),
        append(VIsP,VIsQ,VIs).
q_forall_var_insts_(or(P,Q),Vs,VIs) :-
        !,
        q_forall_var_insts_(P,Vs,VIsP),
        q_forall_var_insts_(Q,Vs,VIsQ),
        append(VIsP,VIsQ,VIs).
q_forall_var_insts_(xor(P,Q),Vs,VIs) :-
        !,
        q_forall_var_insts_(P,Vs,VIsP),
        q_forall_var_insts_(Q,Vs,VIsQ),
        append(VIsP,VIsQ,VIs).
q_forall_var_insts_(imp(P,Q),Vs,VIs) :-
        !,
        q_forall_var_insts_(P,Vs,VIsP),
        q_forall_var_insts_(Q,Vs,VIsQ),
        append(VIsP,VIsQ,VIs).
q_forall_var_insts_(iff(P,Q),Vs,VIs) :-
        !,
        q_forall_var_insts_(P,Vs,VIsP),
        q_forall_var_insts_(Q,Vs,VIsQ),
        append(VIsP,VIsQ,VIs).
q_forall_var_insts_(exists(_,P),Vs,VIs) :-
        !,
        q_forall_var_insts_(P,Vs,VIs).
q_forall_var_insts_(forall(X,imp(P,Q)),Vs,VIs) :-
        !,
        q_forall_var_insts_(P,[X|Vs],VIsP),
        q_forall_var_insts_(Q,Vs,VIsQ),
        append(VIsP,VIsQ,VIs).
q_forall_var_insts_(forall(_,P),Vs,VIs) :-
        !,
        q_forall_var_insts_(P,Vs,VIs).
q_forall_var_insts_(P,Vs,VIs) :-
        var_insts(P,Vs,VIs).

var_insts(P,Vs,VIs) :-
        var_insts_(P,Vs,[],VIs).

var_insts_(_,[],VIs,VIs) :- !.
var_insts_(P,[V|Vs],VIsAcc0,VIs) :-
        P =.. [Prop|Args],
        memberchk(V,Args), !,
        scoped_prop(Args,V,SArgs,X),
        SP =.. [Prop|SArgs],
        findall(V=X,user:property(SP),VIsAcc1),
        append(VIsAcc0,VIsAcc1,VIsAcc2),
        var_insts_(P,Vs,VIsAcc2,VIs).
var_insts_(P,[_|Vs],VIsAcc,VIs) :-
        var_insts_(P,Vs,VIsAcc,VIs).

scoped_prop([],_,[],_) :- !.
scoped_prop([V|As],V,[X|SArgs],X) :-
        !, scoped_prop(As,V,SArgs,X).
scoped_prop([_|As],V,[_|SArgs],X) :-
        scoped_prop(As,V,SArgs,X).
