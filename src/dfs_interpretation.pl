/*
 * Copyright 2017-2022 Harm Brouwer <me@hbrouwer.eu>
 *     and Noortje Venhuizen <njvenhuizen@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

:- module(dfs_interpretation,
        [
                dfs_variables/1,
                dfs_entities/2,
                dfs_constant_instantiations/2,
                dfs_term_instantiations/3,
                dfs_init_g/2,
                dfs_assign/4,
                dfs_terms_to_entities/3,
                dfs_formula_to_fol/2,
                dfs_formulas_to_fol/2,
                dfs_interpret/2,
                dfs_interpret/3
        ]).

:- use_module(library(lists)).

:- use_module(dfs_logic).

/** <module> Model-theoretic interpretation

Model-theoretic interpretation.
*/

%!      dfs_variables(-Variables) is det.
%
%       Variables is a list of variables.

dfs_variables([x,y,z|Vars]) :- 
        enumerate_term('x',10,Vars).

%!      dfs_entities(+N,-Entities) is det.
%
%       Entities is a list of N model entities.

dfs_entities(N,Es) :-
        enumerate_term('e',N,Es).

%!      enumerate_term(+Term,+N,-EnumTerms) is det.

enumerate_term(T,N,ETs) :-
        N0 is N + 1,
        enumerate_term_(T,N0,1,ETs).

enumerate_term_(_,N,N,[]) :- !.
enumerate_term_(T,N,NAcc,[ET|ETs]) :-
        atomic_concat(T,NAcc,ET),
        NAcc0 is NAcc + 1,
        enumerate_term_(T,N,NAcc0,ETs).

%!      dfs_constant_instantiations(+Model,-ConstantInstantiations) is det.
%
%       ConstantInstantiations is a list of all constant instantiations in
%       Model.

dfs_constant_instantiations((_,Vm),CIs) :-
        findall((C,E),member(C=E,Vm),CIs).

%!      dfs_term_instantiations(+Model,+G,-TermInstantiations) is det.
%
%       TermInstantiations is a list of all constant and variable
%       instantiations in Model.

dfs_term_instantiations(M,G,TIs) :-
        dfs_constant_instantiations(M,CIs),
        append(CIs,G,TIs).

%!      dfs_init_g(+Model,-G) is det.
%
%       Initializes the assignment function G :: Var -> Um. Variables are
%       assigned by iterating over the entities in the Model universe.

dfs_init_g(([],_),[]) :- !.
dfs_init_g((Um,_),G) :-
        dfs_variables(Vars),
        dfs_init_g_(Vars,Um,Um,G).

dfs_init_g_([],_,_,[]).
dfs_init_g_([V|Vs],[],Um,G) :-
        !, dfs_init_g_([V|Vs],Um,Um,G).
dfs_init_g_([V|Vs],[E|Es],Um,[(V,E)|G]) :-
        !, dfs_init_g_(Vs,Es,Um,G).

%!      dfs_assign(+G,+Model,+Assignments,-Gprime) is det.
%
%       Updates the assignment function G of Model with variable Assignments,
%       yielding assignment function G'.

dfs_assign(G,(Um,_),As,Gp) :-
        reverse(As,AsRev),
        dfs_assign_(G,Um,AsRev,[],GpRev),
        reverse(GpRev,Gp).

dfs_assign_([],_,_,Gp,Gp).
dfs_assign_([(V,E)|G],Um,As,GpAcc,Gp) :-        %% V = E
        \+ memberchk(V/_,As), !,
        dfs_assign_(G,Um,As,[(V,E)|GpAcc],Gp).
dfs_assign_([(V,_)|G],Um,As,GpAcc,Gp) :-        %% V = E'
        memberchk(V/Ep,As),
        memberchk(Ep,Um), !,
        dfs_assign_(G,Um,As,[(V,Ep)|GpAcc],Gp).
dfs_assign_([(V,_)|G],Um,As,GpAcc,Gp) :-        %% V = g(V')
        memberchk(V/g(Vp),As),
        ( memberchk((Vp,Ep),G) ; memberchk((Vp,Ep),GpAcc) ), !,
        dfs_assign_(G,Um,As,[(V,Ep)|GpAcc],Gp).
dfs_assign_([(V,E)|G],Um,As,GpAcc,Gp) :-        %% V = g(V)
        memberchk(V/g(V),As),
        dfs_assign_(G,Um,As,[(V,E)|GpAcc],Gp).

%!      dfs_terms_to_entities(?Terms,+TermInstantiations,?Entities) is det.
%
%       Maps Terms into Entities (or vice versa), given their instantiations.

dfs_terms_to_entities([],_,[]).
dfs_terms_to_entities([T|Ts],TIs,[E|Es]) :-
        memberchk((T,E),TIs),
        dfs_terms_to_entities(Ts,TIs,Es).

%!      dfs_formula_to_fol(+Formula,-FOLFormula) is det.
%
%       Convert FOL and/or DRS formula into first-order logic
%       formula.

dfs_formula_to_fol(drs(UK,CK),FF) :-
        !, drs_to_fol(drs(UK,CK),FF).
dfs_formula_to_fol(F,F).

%!      dfs_formulas_to_fol(+Formulas,-FOLFormulas) is det.
%
%       Convert FOL and/or DRS formulas into first-order logic
%       formulas.

dfs_formulas_to_fol([],[]).
dfs_formulas_to_fol([F|Fs],[FF|FFs]) :-
        dfs_formula_to_fol(F,FF),
        dfs_formulas_to_fol(Fs,FFs).

%!      dfs_interpret(+Formula,+Model) is semidet.
%!      dfs_interpret(+FormulaSet,+Model) is semidet.
%
%       Evaluates the truth value of Formula in Model, given an initial
%       assignment function G.

dfs_interpret(P,M) :-
        dfs_init_g(M,G),
        dfs_interpret(P,M,G).

%!      dfs_interpret(+Formula,+Model,+G) is semidet.
%!      dfs_interpret(+FormulaSet,+Model,+G) is semidet.
%
%       Evaluates the truth value of Formula in Model, given the assignment
%       function G.

dfs_interpret([P|Ps],M,G) :-
        !, % set of formulas 
        dfs_conjoin([P|Ps],F),
        dfs_interpret(F,M,G).
dfs_interpret(T1=T2,M,G) :- 
        !, % t1 = t2
        dfs_term_instantiations(M,G,TIs),
        dfs_terms_to_entities([T1],TIs,[E]),
        dfs_terms_to_entities([T2],TIs,[E]).
dfs_interpret(neg(P),M,G) :-
        !, % !P
        \+ dfs_interpret(P,M,G).
dfs_interpret(and(P,Q),M,G) :- 
        !, % P & Q
        dfs_interpret(P,M,G), dfs_interpret(Q,M,G).
dfs_interpret(or(P,Q),M,G) :-
        !, % P | Q
        ( dfs_interpret(P,M,G), ! ; dfs_interpret(Q,M,G) ).
dfs_interpret(exor(P,Q),M,G) :-
        !, % P (+) Q
        ( dfs_interpret(P,M,G), \+ dfs_interpret(Q,M,G), !
        ; \+ dfs_interpret(P,M,G), dfs_interpret(Q,M,G) ).
dfs_interpret(imp(P,Q),M,G) :- 
        !, % P --> Q
        ( \+ dfs_interpret(P,M,G), ! ; dfs_interpret(Q,M,G) ).
dfs_interpret(iff(P,Q),M,G) :- 
        !, % P <-> Q
        ( dfs_interpret(P,M,G), dfs_interpret(Q,M,G), !
        ; \+ dfs_interpret(P,M,G), \+ dfs_interpret(Q,M,G) ).
dfs_interpret(exists(X,P),M,G) :- 
        !, % ∃x P
        q_exists(X,P,M,G).
dfs_interpret(forall(X,P),M,G) :-
        !, % ∀x P
        q_forall(X,P,M,G).
dfs_interpret(top,_,_) :-
        !, % ⊤
        true.
dfs_interpret(bottom,_,_) :-
        !, % ⊥
        false.
dfs_interpret(P,M,G) :-
        % R(t1,...,tn)
        P =.. [Pred|Args],
        dfs_term_instantiations(M,G,TIs),
        dfs_terms_to_entities(Args,TIs,Es),
        eval(Pred,Es,M).

%!      q_exists(+Var,+Formula,+Model,+G) is semidet.
%
%       True iff there is a single instantiation of Var in the set of entities
%       Es for which Formula holds in the Model.

q_exists(X,P,(Um,Vm),G) :-
        q_exists_(X,P,Um,(Um,Vm),G).

q_exists_(_,_,[],_,_) :- !, false.
q_exists_(X,P,[E|Es],M,G) :-
        dfs_assign(G,M,[X/E],Gp),
        (  dfs_interpret(P,M,Gp)
        -> true
        ;  q_exists_(X,P,Es,M,G)).

%!      q_forall(+Var,+Formula,+Model,+G) is semidet.
%
%       True iff for all instantions of Var in the set of entities Es, Formula
%       holds in the Model.

q_forall(X,P,(Um,Vm),G) :-
        q_forall_(X,P,Um,(Um,Vm),G).

q_forall_(_,_,[],_,_) :- !, true.
q_forall_(X,P,[E|Es],M,G) :-
        dfs_assign(G,M,[X/E],Gp),
        dfs_interpret(P,M,Gp),
        q_forall_(X,P,Es,M,G).

%!      eval(+Property,+Entities,+Model) is semidet.
%
%       Evaluate the truth value of Property for Entities in the Model.

eval(Prop,[E],(_,Vm)) :-        %% unary predicates
        !, eval_(Prop,[E],Vm).
eval(Prop,Es,(_,Vm)) :-         %% n-ary predicates
        eval_(Prop,[Es],Vm).

% eval_(_,_,[]) :- !, false. %% (note: uncommenting has same effect)
eval_(Prop,Es,[R|Rs]) :-
        R =.. [RProp|_],
        Prop \= RProp, !,
        eval_(Prop,Es,Rs).
eval_(Prop,Es,[R|_]) :-
        R =.. [Prop|[REs]],
        intersection(Es,REs,Es).
