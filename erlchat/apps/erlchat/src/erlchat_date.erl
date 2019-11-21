%%%-------------------------------------------------------------------
%%% @author fu
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. 十一月 2019 9:51
%%%-------------------------------------------------------------------
-module(erlchat_date).
-author("fu").

%% API
-export([localTimeFormat/1]).

localTimeFormat(Time) ->
  {{Year , Month , Day} , {Hour , Minute , Second}} = Time,
  list_to_binary(io_lib:format("~2..0w:~2..0w",
    [Hour,Minute])).
