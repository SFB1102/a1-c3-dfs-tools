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
 
:- module(dfs_information_theory,
        [
                dfs_surprisal/3,
                dfs_surprisal/4,
                dfs_entropy/2,
                dfs_entropy/3,
                dfs_delta_entropy/3,
                dfs_delta_entropy/4,

                dfs_syntactic_surprisal/3,
                dfs_syntactic_entropy/2,
                dfs_syntactic_delta_entropy/3,
                dfs_semantic_surprisal/4,
                dfs_semantic_entropy/3,
                dfs_semantic_delta_entropy/4
        ]).

:- use_module(library(lists)).
:- use_module(library(ordsets)).

:- use_module(dfs_logic).
:- use_module(dfs_probabilities).
:- use_module(dfs_sentences).
:- use_module(dfs_vector_space).

/** <module> Information theory

Information theoretic metrics for vectors, and for formulas given a set of
models.
*/

%!      dfs_surprisal(+Vector1,+Vector2,-Surprisal) is det.
%!      dfs_surprisal(+Formula1,+Formula2,+ModelSet,-Surprisal) is det.
%!      dfs_surprisal(+Formula1,+Formula2,+ModelMatrix,-Surprisal) is det.
%
%       Surprisal of P given Q, where P and Q are either vectors or formulas.
%
%       ==
%       surprisal(P,Q) = -log Pr(P|Q)
%       ==

dfs_surprisal(VP,VQ,S) :-
        dfs_cond_probability(VP,VQ,PrPgQ),
        dfs_surprisal_(PrPgQ,S).

dfs_surprisal(P,Q,Ms,S) :-
        dfs_cond_probability(P,Q,Ms,PrPgQ),
        dfs_surprisal_(PrPgQ,S).

dfs_surprisal_(PrPgQ,S) :-
        (  PrPgQ > 0.0
        -> S is -log(PrPgQ)
        ;  S is inf ).     

%!      dfs_entropy(+Vector,-Entropy) is det.
%!      dfs_entropy(+Formula,+ModelSet,-Entropy) is det.
%!      dfs_entropy(+Formula,+ModelMatrix,-Entropy) is det.
%
%       Entropy of P, where P is either a vector or a formula.
%
%       ==
%       H(P) = - sum_{s in S} Pr(s|P) * log Pr(s|P)
%       ==
%
%       where the set S consists of all possible points in the DFS space that
%       are fully specified with respect to the atomic propositions; that is,
%       each point s in S constitutes a unique logical combination of all
%       atomic propostions.

dfs_entropy(VP,H) :-
        sum_list(VP,S),
        dfs_entropy_(VP,S,0,H).

dfs_entropy(P,Ms,H) :-
        dfs_vector(P,Ms,VP),
        dfs_entropy(VP,H).
        
dfs_entropy_([],_,HAcc,H) :-
        H is -HAcc.
dfs_entropy_([U|Us],S,HAcc,H) :-
        PrUgP is (1.0 * U) / S,
        (  PrUgP > 0.0
        -> HAcc0 is HAcc + PrUgP * log(PrUgP)
        ;  HAcc0 is HAcc ),
        dfs_entropy_(Us,S,HAcc0,H).

%!      dfs_delta_entropy(+Vector1,+Vector2,-DeltaH) is det.
%!      dfs_delta_entropy(+Formula1,+Formula2,+ModelSet,-DeltaH) is det.
%!      dfs_delta_entropy(+Formula1,+Formula2,+ModelMatrix,-DeltaH) is det.
%
%       Entropy delta of P given Q, where P and Q are either vectors or formulas.
%
%       ==
%       DH(P,Q) = H(Q) - H(P)
%       ==

dfs_delta_entropy(VP,VQ,DH) :-
        dfs_entropy(VP,HP),
        dfs_entropy(VQ,HQ),
        DH is HQ - HP.

dfs_delta_entropy(P,Q,Ms,DH) :-
        dfs_entropy(P,Ms,HP),
        dfs_entropy(Q,Ms,HQ),
        DH is HQ - HP.

                %%%%%%%%%%%%%%%%%%%
                %%%% sentences %%%%
                %%%%%%%%%%%%%%%%%%%

%!      dfs_syntactic_surprisal(+Word,+Prefix,-Surprisal) is det.
%
%       Syntactic surprisal of a word given a prefix.
%       
%       ==
%       S(w_i+1) = -log(P(w_i+1|w_1...i))
%                = log(P(w_1...i)) - log(P(w_1...i+1))
%                = log(freq(w_1...i)) - log(freq(w_1...i+1))
%       ==

dfs_syntactic_surprisal(W,Prefix,S) :-
        append(Prefix,[W],PrefixW),
        dfs_prefix_frequency(Prefix, F),
        dfs_prefix_frequency(PrefixW,FW),
        S is log(F) - log(FW).

%!      dfs_syntactic_entropy(+Prefix,-Entropy) is det.
%
%       Syntactic entropy for a prefix.
%
%       ==
%       H(w_i) = -sum_(w_1...i,w_i+1...n)
%                Pr(w_1...i,w_i+1...n|w_1...i)
%                * log(Pr(w_1...i,w_i+1...n|w_1...i))
%       ==

dfs_syntactic_entropy(Prefix,H) :-
        dfs_prefix_continuations(Prefix,Cs),
        length(Cs,TF),
        list_to_ord_set(Cs,Cs0),
        dfs_syntactic_entropy_(Cs0,TF,0,H).

dfs_syntactic_entropy_([],_,H,H).
dfs_syntactic_entropy_([(C,_)|Cs],TF,HAcc,H) :-
        dfs_sentence_frequency(C,F),
        Pr is F / TF,
        HAcc0 is HAcc - Pr * log(Pr),
        dfs_syntactic_entropy_(Cs,TF,HAcc0,H).

%!      dfs_syntactic_delta_entropy(+Word,+Prefix,-DeltaH) is det.
%
%       Syntactic entropy delta for a word given a prefix.
%
%       ==
%       DH(w_i+1) = H(w_i) - H(w_i+1)
%       ==

dfs_syntactic_delta_entropy(W,Prefix,DH) :-
        append(Prefix,[W],PrefixW),
        dfs_syntactic_entropy(Prefix, H),
        dfs_syntactic_entropy(PrefixW,HW),
        DH is H - HW.

%!      dfs_semantic_surprisal(+Word,+Prefix,+ModelSet,-Surprisal) is det.
%
%       Semantic suprisal for a word given a prefix.
%
%       ==
%       S(w_i+1) = -log(Pr(v(w_1...i+1)|w_1...i))
%       ==
%
%       where v(w_1...i) is the disjunction of all semantics consistent with
%       the prefix w_1...w_i.

dfs_semantic_surprisal(W,Prefix,MS,S) :-
        append(Prefix,[W],PrefixW),
        dfs_prefix_continuations(Prefix, Cs),
        dfs_prefix_continuations(PrefixW,CsW),
        findall(P, member((_,P), Cs), Ps),
        findall(PW,member((_,PW),CsW),PsW),
        dfs_disjoin(Ps, Disj),
        dfs_disjoin(PsW,DisjW),
        dfs_surprisal(DisjW,Disj,MS,S).

%!      dfs_semantic_entropy(+Prefix,+ModelSet,-Entropy) is det.
%
%       Semantic entropy for a prefix.
%
%       ==
%       H(w_i) = - sum_(foreach s in S) Pr(s|v(w_1...i))
%                * log(Pr(s|v(w_1...i))) 
%       ==
%
%       where v(w_1...i) is the disjunction of all semantics consistent with
%       the prefix w_1...w_i.

dfs_semantic_entropy(Prefix,MS,H) :-
        dfs_prefix_continuations(Prefix,Cs),
        findall(P,member((_,P),Cs),Ps),
        dfs_disjoin(Ps,Disj),
        dfs_entropy(Disj,MS,H).

%!      dfs_semantic_delta_entropy(+Word,+Prefix,+ModelSet,-DeltaH) is det.
%
%       Semantic entropy delta for a word given a prefix.
%
%       ==
%       DH(w_i+1) = H(w_i) - H(w_i+1)
%       ==

dfs_semantic_delta_entropy(W,Prefix,MS,DH) :-
        append(Prefix,[W],PrefixW),
        dfs_semantic_entropy(Prefix, MS,H),
        dfs_semantic_entropy(PrefixW,MS,HW),
        DH is H - HW.
