%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Copyright 2012- Klarna AB
%%% Copyright 2014- AUTHORS
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% @copyright 2012- Klarna AB, AUTHORS
%%%
%%% @doc Built-in JSON callback functions.
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration =======================================================
-module(katt_callbacks_json).

%%%_* Exports ==================================================================
%% API
-export([ recall_body/4
        , parse/5
        , validate_body/4
        , validate_type/7
        , parse_json/1
        ]).

%%%_* Includes =================================================================
-include("katt.hrl").

%%%_* API ======================================================================

%% @doc Recall all params inside application/json or application/*+json content.
%% @end
-spec recall_body( boolean()
                 , any()
                 , params()
                 , callbacks()
                 ) -> any().
recall_body(true = _JustCheck, [Hdrs, _Bin], _Params, _Callbacks) ->
  katt_util:is_json_content_type(Hdrs);
recall_body(false = _JustCheck, [_Hdrs, Bin], [], _Callbacks) ->
  Bin;
recall_body(JustCheck, Any, [{_K, [H|_]} | Next], Callbacks) when is_tuple(H) ->
  recall_body(JustCheck, Any, Next, Callbacks);
recall_body(false = _JustCheck, [Hdrs, Bin0], [{K0, V0} | Next], Callbacks) ->
  K = ?RECALL_BEGIN_TAG ++ K0 ++ ?RECALL_END_TAG,
  REK = katt_util:escape_regex(K),
  V = katt_util:maybe_json_string(V0),
  REV = katt_util:escape_regex(V),
  Bin1 = re:replace( Bin0
                   , "\"" ++ REK ++ "\""
                   , REV
                   , [{return, binary}, global]),
  Bin = katt_callbacks:recall(text, Bin1, [{K0, V0}], Callbacks),
  recall_body(false, [Hdrs, Bin], Next, Callbacks).


%% @doc Parse the body of e.g. an HTTP response.
%% @end
-spec parse( boolean()
           , headers()
           , body()
           , params()
           , callbacks()
           ) -> any().
parse(true = _JustCheck, Hdrs, _Body, _Params, _Callbacks) ->
  katt_util:is_json_content_type(Hdrs);
parse(false = _JustCheck, _Hdrs, null, _Params, _Callbacks) ->
  [];
parse(false = _JustCheck, Hdrs, Body, _Params, _Callbacks) ->
  case katt_util:is_json_content_type(Hdrs) of
    true ->
      parse_json(Body);
    false ->
      katt_util:from_utf8(Body)
  end.


validate_body( true = _Justcheck
             , #katt_response{headers=EHdrs}
             , #katt_response{headers=AHdrs}
             , _Callbacks
             ) ->
  katt_util:is_json_content_type(EHdrs) andalso
    katt_util:is_json_content_type(AHdrs);
validate_body( false = _Justcheck
             , #katt_response{parsed_body=E}
             , #katt_response{parsed_body=A}
             , Callbacks
             ) ->
  katt_util:validate("/body", E, A, ?MATCH_ANY, Callbacks).


validate_type( true = _JustCheck
             , Type
             , _ParentKey
             , _Options
             , _Actual
             , _ItemsMode
             , _Callbacks
             ) when Type =:= "set" orelse
                    Type =:= "runtime_value" orelse
                    Type =:= "runtime_validation" ->
  true;
validate_type( true = _JustCheck
             , _Type
             , _ParentKey
             , _Options
             , _Actual
             , _ItemsMode
             , _Callbacks
             ) ->
  false;
validate_type( false = _JustCheck
             , "set"
             , ParentKey
             , Options
             , Actual
             , ItemsMode
             , Callbacks
             ) ->
  katt_validate_type:validate_type_set( ParentKey
                                      , Options
                                      , Actual
                                      , ItemsMode
                                      , Callbacks
                                      );
validate_type( false = _JustCheck
             , "runtime_value"
             , ParentKey
             , Options
             , Actual
             , ItemsMode
             , Callbacks
             ) ->
  katt_validate_type:validate_type_runtime_value( ParentKey
                                                , Options
                                                , Actual
                                                , ItemsMode
                                                , Callbacks
                                                );
validate_type( false = _JustCheck
             , "runtime_validation"
             , ParentKey
             , Options
             , Actual
             , ItemsMode
             , Callbacks
             ) ->
  katt_validate_type:validate_type_runtime_validation( ParentKey
                                                     , Options
                                                     , Actual
                                                     , ItemsMode
                                                     , Callbacks
                                                     );
validate_type( false = _JustCheck
             , _Type
             , _ParentKey
             , _Options
             , _Actual
             , _ItemsMode
             , _Callbacks
             ) ->
  fail.

%%%_* Internal =================================================================

-ifdef(BARE_MODE).
parse_json(_Bin) ->
  throw(bare_mode).
-else.

parse_json(Bin) when is_binary(Bin) andalso size(Bin) =:= 0 ->
  [];
parse_json(Bin) ->
  normalize_jsx(jsx:decode(Bin, [{return_maps, false}])).

%% Convert binary strings,
%% sort object keys and array items,
%% add "array" identifier
normalize_jsx([{_, _}|_] = Items0) ->
  Items1 = lists:sort([ {katt_util:from_utf8(Key), normalize_jsx(Value)}
                        || {Key, Value} <- Items0
                      ]),
  Type = proplists:get_value(?TYPE, Items1, struct),
  Items = case Type of
            struct ->
              Items1;
            _ ->
              proplists:delete(?TYPE, Items1)
          end,
  {Type, Items};
normalize_jsx([{}] = _Items) ->
  {struct, []};
normalize_jsx(Items0) when is_list(Items0) ->
  Items1 = [ normalize_jsx(Item)
             || Item <- Items0
           ],
  ItemsMode = case lists:member(?UNEXPECTED, Items1) of
                true -> [{?MATCH_ANY, ?UNEXPECTED}];
                false -> []
              end,
  Items2 = lists:delete(?UNEXPECTED, Items1),
  MatchAny = case lists:member(?MATCH_ANY, Items2) of
               true -> [{?MATCH_ANY, ?MATCH_ANY}];
               false -> []
             end,
  Items3 = lists:delete(?MATCH_ANY, Items2),
  Items = katt_util:enumerate(Items3),
  {array, Items ++ ItemsMode ++ MatchAny};
normalize_jsx(Str) when is_binary(Str) ->
  katt_util:from_utf8(Str);
normalize_jsx(Value) ->
  Value.

-endif.
