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

:- module(coals,
        [
                coals_vectors/3,
                coals_binary_vectors/3,
                coals_padded_binary_vectors/4,
                coals_write_vectors/2
        ]).

:- use_module(library(clpfd)).
:- use_module(library(debug)). % topic: coals
:- use_module(library(lists)).
:- use_module(library(random)).

:- use_module(dfs_sentences).

:- public
        user:coals_random_seed/1.

% YAP compatibility
:- prolog_flag(version_data,V),
        V =.. [P|_],
        (  P == yap
        -> use_module('../yap/swi_predicates.pl'),
           use_module('../yap/yap_random.pl')
        ;  true ).

/** <module> COALS

Correlated Occurrence Analogue to Lexical Semantics (COALS) interface for
Definite Clause Grammars (DCG).

@see Rohde, D. L. T., Gonnerman, L. M., & Plaut, D. C. (2005). An Improved
        Model of Semantic Similarity Based on Lexical Co-Occurrence.
*/

                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %%%% real-valued COALS vectors %%%%
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%!      coals_vectors(+WindowType,+WindowSize,-CoalsVectors) is det.
%
%       CoalsVectors is a list of (Word,Vector) tuples, where Vector is a
%       real-valued COALS vector, derived from a DCG using a WindowType of
%       WindowSize.

coals_vectors(WType,WSize,WCVs) :-
        derive_real_coals_vectors(WType,WSize,CVs),
        dfs_words(Words),
        zip_words_and_vectors(Words,CVs,WCVs).

%!      derive_real_coals_vectors(+WindowType,+WindowSize,-CoalsVectors)
%!              is det.
%
%       Derive real-valued COALS vectors from a DCG, using WindowType of
%       WindowSize.
%
%       First, a co-occurrence frequency matrix is constructed for all
%       words generated by the DCG. On a sentence-by-sentence basis, the 
%       co-occurrence frequency for two words 'a' and 'b' is determined using
%       a window of WindowSize, such that 'b' co-occurs with 'a' if it occurs 
%       within WindowSize words to the left or right of 'a'. The frequency of 
%       co-occurrence, then, is weighed using either a 'flat' or 'ramped' 
%       WindowType. The former uniformly weighs the co-occurrence frequency of
%       'a' and 'b' with '1' regardless of 'b's position within the window,
%       whereas the latter weighs it according to 'b's proximity to a. For
%       instance, for WindowSize = 4:
%
%           flat: 1 1 1 1 [a] 1 1 1 1       ramped: 1 2 3 4 [a] 4 3 2 1
%
%       Next, the co-occurrence matrix is converted into a normalized pairwise
%       correlation matrix, in which positive correlations are replaced by
%       their square root, and negative correlations by zero.

derive_real_coals_vectors(WType,WSize,CVs) :-
        findall(Sen,dfs_sentences:sentence((Sen,_)),Sens),
        dfs_words(Words),
        frequency_matrix(Words,Words,Sens,WType,WSize,FM),
        correlation_matrix(FM,CVs).

%!      frequency_matrix(+RowWords,+ColWords,+Sentences,+WindowType,
%!              +WindowSize,-FMatrix) is det.
%
%       FMatrix is a co-coccurence frequency matrix of all RowWords with all
%       ColWords in Sentences. Frequencies are determined using a WindowType
%       window of WindowSize.

frequency_matrix([],_,_,_,_,[]).
frequency_matrix([RWord|RWords],CWords,Sens,WT,WS,[FV|FVs]) :-
        frequency_matrix_(CWords,RWord,Sens,WT,WS,FV),
        debug(coals,'Counts: ~s -> ~w',[RWord,FV]),
        frequency_matrix(RWords,CWords,Sens,WT,WS,FVs).

frequency_matrix_([],_,_,_,_,[]).
frequency_matrix_([CWord|CWords],RWord,Sens,WT,WS,[F|Fs]) :-
        windowed_frequency(Sens,RWord,CWord,WT,WS,0,F),
        frequency_matrix_(CWords,RWord,Sens,WT,WS,Fs).

%!      windowed_frequency(+Sentences,+RowWord,+ColWord,+WindowType,
%!              +WindowSize,-Freq) is det.
%
%       Freq is the co-occurrence frequency of RowRord and ColWord in
%       Sentence, given a WindowType window of WindowSize.

windowed_frequency([],_,_,_,_,F,F).
windowed_frequency([Sen|Sens],RWord,CWord,WT,WS,FAcc,F) :-
        memberchk(RWord,Sen),
        memberchk(CWord,Sen), 
        !,
        findall(F0,
          ( append(LWindowRev,[RWord|RWindow],Sen),
            reverse(LWindowRev,LWindow),
            windowed_frequency_(LWindow,CWord,WT,WS,0,LF),
            windowed_frequency_(RWindow,CWord,WT,WS,0,RF),
            F0 is LF + RF ),
        F0s),
        sumlist(F0s,SF),
        FAcc0 is FAcc + SF,
        windowed_frequency(Sens,RWord,CWord,WT,WS,FAcc0,F).
windowed_frequency([_|Sens],RWord,CWord,WT,WS,FAcc,F) :-
        windowed_frequency(Sens,RWord,CWord,WT,WS,FAcc,F).

windowed_frequency_([],_,_,_,F,F) :- !.
windowed_frequency_(_, _,_,0,F,F) :- !.
windowed_frequency_([Word|Words],Word,WT,N,FAcc,F) :-
        WT = 'flat', !,
        FAcc0 is FAcc + 1,
        N0 is N - 1,
        windowed_frequency_(Words,Word,WT,N0,FAcc0,F).
windowed_frequency_([Word|Words],Word,WT,N,FAcc,F) :-
        WT = 'ramped', !,
        FAcc0 is FAcc + N,
        N0 is N - 1,
        windowed_frequency_(Words,Word,WT,N0,FAcc0,F).
windowed_frequency_([_|Words],Word,WT,N,FAcc,F) :-
        N0 is N - 1,
        windowed_frequency_(Words,Word,WT,N0,FAcc,F).

%!      correlation_matrix(+FreqMatrix,-CorMatrix) is det.
%
%       CorMatrix is a matrix of normalized pairwise correlations derived from
%       FreqMatrix. 
%
%       First, each co-occurence frequency w_{a,b} between words 'a' and 'b'
%       is converted into a word pair correlation:
%
%                     T * w_{a,b} - sum_j w_{a,j} * sum_i w_{i,b}
%           w'{a,b} = -------------------------------------------
%                     sqrt(sum_j w_{a,j} * (T - sum_j w_{a,j}) *
%                          sum_i w_{i,b} * (T - sum_i w_{i,b}))
%
%       where: T = sum_j sum_i w_{i,j}
%
%       Next, these correlations are normalized:
%
%                           | 0                 if w'{a,b} < 0
%           norm(w'{a,b}) = |
%                           | sqrt(w'_{a,b})    otherwise

correlation_matrix(FM,CM) :-
        matrix_totals(FM,RTs,CTs,GT),
        correlation_matrix_(FM,RTs,CTs,GT,CM).

correlation_matrix_([],[],_,_,[]).
correlation_matrix_([V|Vs],[RT|RTs],CTs,GT,[CV|CVs]) :-
        correlation_matrix__(V,RT,CTs,GT,CV),
        debug(coals,'Correlations: ~w => ~w',[V,CV]),
        correlation_matrix_(Vs,RTs,CTs,GT,CVs).

correlation_matrix__([],_,[],_,[]).
correlation_matrix__([F|Fs],RT,[CT|CTs],GT,[C|Cs]) :-
        N is GT * F - RT * CT,
        D is sqrt(RT * (GT - RT) * CT * (GT - CT)),
        (  N > 0.0,             % norm: 0               if w'{a,b} < 0
           D > 0.0
        -> C is sqrt(N / D)     % norm: sqrt(w'{a,b})   otherwise
        ;  C is 0.0 ),
        correlation_matrix__(Fs,RT,CTs,GT,Cs).

%!      matrix_totals(+Matrix,-RowTotals,-ColTotals,-GrandTotal)
%!              is det.
%
%       RowMatrix is a vector of row totals from Matrix, ColTotals a vector
%       of column totals, and GrantTotal the overall total.

matrix_totals(M,RTs,CTs,GT) :-
        matrix_totals_(M,RTs),
        transpose(M,TM),
        matrix_totals_(TM,CTs),
        sumlist(RTs,GT).

matrix_totals_([],[]).
matrix_totals_([V|Vs],[VC|VCs]) :-
        sumlist(V,VC),
        matrix_totals_(Vs,VCs).

%!      zip_words_and_vectors(+Words,+Vectors,-Tuples) is det.
%
%       Tuples is a list of (Word,Vector) tuples, zipped together from Words
%       and Vectors.

zip_words_and_vectors([],[],[]).
zip_words_and_vectors([W|Ws],[CV|CVs],[(W,CV)|Ts]) :-
        zip_words_and_vectors(Ws,CVs,Ts).

%!      coals_write_vectors(+Tuples,+File) is det.
%
%       Writes a list of (Word,Vector) Tuples to File in CSV format.

coals_write_vectors(Ts,File) :-
        open(File,write,Stream),
        coals_write_vectors_(Ts,Stream),
        close(Stream).

coals_write_vectors_([],_).
coals_write_vectors_([(W,CV)|Ts],Stream) :-
        format(Stream,'~w,',[W]),
        coals_format_vector(CV,Stream),
        format(Stream,'~n',[]),
        coals_write_vectors_(Ts,Stream).

%!      coals_format_vector(+Vector,+Stream) is det.
%
%       Write Vector to Stream in CSV format.

coals_format_vector([U],Stream) :-
        !, format(Stream,'~f',U).
coals_format_vector([U|Us],Stream) :-
        format(Stream,'~f,',U),
        coals_format_vector(Us,Stream).

                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %%%% binary COALS vectors %%%%
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%!      coals_binary_vectors(+WindowType,+WindowSize,-CoalsVectors) is det.
%
%       CoalsVectors is a list of (Word,Vector) tuples, where Vector is a
%       binary COALS vector, derived from a DCG using a WindowType of
%       WindowSize. Binary COALS vectors are derived from real-valued COALS
%       vectors, by setting positive correlations to hot bits (i.e., 1s).

coals_binary_vectors(WType,WSize,WCVs) :-
        derive_real_coals_vectors(WType,WSize,CVs),
        binary_matrix(CVs,BCVs),
        dfs_words(Words),
        zip_words_and_vectors(Words,BCVs,WCVs).

%!      binary_matrix(+CorMatrix,-BinMatrix) is det.
%
%       BinMatrix is a matrix in which all positive correlations in CorMatrix
%       are set to hot bits (i.e., 1s).

binary_matrix([],[]).
binary_matrix([V|Vs],[BV|BVs]) :-
        binary_matrix_(V,BV),
        debug(coals,'Binary: ~w => ~w',[V,BV]),
        binary_matrix(Vs,BVs).

binary_matrix_([],[]).
binary_matrix_([C|Cs],[1|BUs]) :-
        C > 0.0, !,
        binary_matrix_(Cs,BUs).
binary_matrix_([_|Cs],[0|BUs]) :-
        binary_matrix_(Cs,BUs).

%!      coals_padded_binary_vectors(+WindowType,+WindowSize,+NHotPaddingBits,
%!              -CoalsVectors) is det.
%
%       CoalsVectors is a list of (Word,Vector) tuples, where Vector is a
%       binary COALS vector, derived from a DCG using a WindowType of
%       WindowSize. Binary vectors are padded with a a minimal binary
%       identifier containing NHotPaddingBits, in such a way that the
%       identifiers for similar binary vectors do not share any features.

coals_padded_binary_vectors(WType,WSize,NHotPad,WCVs) :-
        derive_real_coals_vectors(WType,WSize,CVs),
        binary_matrix(CVs,BCVs),
        padding_bits(BCVs,NHotPad,NPad),
        append_identifiers(BCVs,NPad,NHotPad,PaddedBCVs),
        dfs_words(Words),
        zip_words_and_vectors(Words,PaddedBCVs,WCVs).

%!      padding_bits(+BinMatrix,+NHotPaddingBits,-NPaddingBits) is det.
%
%       NPaddingBits is the minimal number of padding bits required for
%       identifiers containing NHotPaddingBits. NPaddingBits depends on the
%       number of subsumed binary vectors (MaxSub) in BinMatrix:
%
%           NPaddingBits = MaxSub * NHotPaddingsBits

padding_bits(BVs,NPadHot,NPad) :-
        list_to_ord_set(BVs,UBVs),
        padding_bits_(UBVs,BVs,NPadHot,0,NPad).

padding_bits_([],_,NPadHot,MaxSub,NPad) :-
        NPad is MaxSub * NPadHot,
        debug(coals,'Padding bits: ~d * ~d = ~d',[MaxSub,NPadHot,NPad]).
padding_bits_([UBV|UBVs],BVs,NPadHot,MaxSub,NPad) :-
        findall(UBV,(member(BV,BVs),subsumes_vector(UBV,BV)),SubBVs),
        length(SubBVs,NumSub),
        (  NumSub > MaxSub
        -> MaxSub0 is NumSub
        ;  MaxSub0 is MaxSub ),
        padding_bits_(UBVs,BVs,NPadHot,MaxSub0,NPad).

%!      subsumes_vector(+GeneralVec,+SpecificVec) is det.
%
%       True iff GeneralVec subsumes SpecificVec, and each vector contains at
%       least one non-zero unit.

subsumes_vector(VG,VS) :-
        memberchk(1,VG),
        memberchk(1,VS),
        subsumes_vector_(VG,VS),
        (  VG == VS
        -> debug(coals,'Subsumption: ~w = ~w',[VG,VS])
        ;  debug(coals,'Subsumption: ~w > ~w',[VG,VS])
        ).

subsumes_vector_([],[]).
subsumes_vector_([0|Us0],[0|Us1]) :-
        !, subsumes_vector_(Us0,Us1).
subsumes_vector_([1|Us0],[0|Us1]) :-
        !, subsumes_vector_(Us0,Us1).
subsumes_vector_([1|Us0],[1|Us1]) :-
        !, subsumes_vector_(Us0,Us1).

%!      append_identifiers(+BinMatrix,+NPaddingBits,+NHotPaddingBits,
%!              +PaddedBinMatrix) is det.
%
%       PaddedBinMatrix contains the vectors of BinMatrix, padded with an
%       identifiers of NPaddingBits, in which NHotPaddingBits are set to
%       hot (i.e., 1).

append_identifiers(BVs,NPad,NPadHot,PBVs) :-
        findall(I,binary_identifier(NPad,NPadHot,I),Is),
        (  current_predicate(user:coals_random_seed/1),
           user:coals_random_seed(Seed)
        -> debug(coals,'Random seed: ~w',[Seed]),
           set_random(seed(Seed))
        ;  true ),
        append_identifiers_(BVs,Is,[],PBVs), !.

append_identifiers_([],_,_,[]).
append_identifiers_([BV|BVs],Is,AIsAcc,[PBV|PBVs]) :-
        random_permutation(Is,Is0),
        member(IV0,Is0),
        \+ ( member((BV1,IV1),AIsAcc),
             ( subsumes_vector(BV1,BV) 
             ; subsumes_vector(BV,BV1) ),
             featural_overlap(IV0,IV1)
           ),
        append(BV,IV0,PBV),
        debug(coals,'Padding: ~w => ~w',[BV,PBV]),
        append_identifiers_(BVs,Is,[(BV,IV0)|AIsAcc],PBVs).

%!      binary_identifier(+NBits,+NHotBits,-Identifier) is det.
%
%       Identifier is a binary identifier of NBits, in which NHotBits are set
%       to hot (i.e., 1).

binary_identifier(NB,NH,I) :-
        binary_identifier_(NB,NH,[],I).

binary_identifier_(0,NH,I,I) :-
        sumlist(I,NH).
binary_identifier_(NB,NH,IAcc,I) :-
        NB > 0,
        NB0 is NB - 1,
        binary_identifier_(NB0,NH,[0|IAcc],I).
binary_identifier_(NB,NH,IAcc,I) :-
        NB > 0,
        sumlist(IAcc,NHI),
        NHI =< NH,
        NB0 is NB - 1,
        binary_identifier_(NB0,NH,[1|IAcc],I).

%!      featural_overlap(+Vector1,+Vector2).
%
%       True iff Vector1 and Vector2 share a feature.

featural_overlap([1|_],[1|_]) :- !.
featural_overlap([_|Us0],[_|Us1]) :-
        featural_overlap(Us0,Us1).
