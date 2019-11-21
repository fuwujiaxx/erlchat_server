%%%-------------------------------------------------------------------
%%% @author fu
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. 十一月 2019 16:21
%%%-------------------------------------------------------------------
-module(erlchat_data).
-author("fu").
-include("erlchat_table.hrl").
-include_lib("stdlib/include/qlc.hrl").

%% API
-export([createTable/0]).
-export([add_tb_uchat_message/5]).
-export([query_tb_uchat_message/2]).
-export([do/1 , doSort/1 , queryMsg/1 , updateMsgUnread/3 , unReadMsgNum/3 , totalUnread/1]).

%%查询用户历史聊天消息
queryMsg(UserId) ->
  Lists = doSort(qlc:q([X || X <- mnesia:table(tb_uchat_message) ,
    (X#tb_uchat_message.from =:= UserId) or (X#tb_uchat_message.to =:= UserId)])),
    Res = lists:map(fun(Item) ->
        FromUserId = Item#tb_uchat_message.from,
        ToUserId = Item#tb_uchat_message.to,
        MsgId = Item#tb_uchat_message.msgId,
        LastTime = erlchat_date:localTimeFormat(Item#tb_uchat_message.lastTime),
        LastMessage = Item#tb_uchat_message.lastMessage,
        UnRead = unReadMsgNum(UserId , FromUserId , ToUserId),
        Data = [#{userid => Uid , message => Msg , msgType => MsgType , fromAvatar => FromAvatar} ||
          {_ , _ , _ , Uid , Msg , MsgType , _ , FromAvatar , _}
          <- do(qlc:q([X || X <- mnesia:table(tb_uchat_message_record),
          X#tb_uchat_message_record.msgId =:= MsgId]))],
        #{<<"portrait">> := FromAvatar , <<"name">> := FromName , <<"company">> := FromCompany , <<"position">> := FromPosition} =
            maps:get(<<"responseBody">> , erlchat_user:userInfo(FromUserId)),
        #{<<"portrait">> := ToAvatar , <<"name">> := ToName , <<"company">> := ToCompany , <<"position">> := ToPosition} =
            maps:get(<<"responseBody">> , erlchat_user:userInfo(ToUserId)),
        if
          FromUserId =:= UserId ->
            #{userid => ToUserId , name => ToName , unread => UnRead , avatar => ToAvatar, lastTime => LastTime , lastMessage => LastMessage ,
              company => ToCompany , position => ToPosition , data => Data};
          true ->
            #{userid => FromUserId , name => FromName , unread => UnRead , avatar => FromAvatar, lastTime => LastTime , lastMessage => LastMessage ,
              company => FromCompany , position => FromPosition , data => Data}
        end
    end , Lists),
    Res.

do(Q) ->
  F = fun() -> qlc:e(Q) end,
  {atomic, Val} = mnesia:transaction(F),
  Val.

doSort(Q) ->
  F = fun() ->
    qlc:e(qlc:keysort(2 , Q , [{order , descending}]))
      end,
  {atomic , Val} = mnesia:transaction(F),
  Val.

%%插入消息
add_tb_uchat_message(From , To , Message , MsgType , Time) ->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message) ,
    ((X#tb_uchat_message.from =:= From) and (X#tb_uchat_message.to =:= To)) or
      ((X#tb_uchat_message.to =:= From) and (X#tb_uchat_message.from =:= To))])),
  LastMessage = Message,
  if
    length(Lists) =:= 1 ->
      Record = lists:nth(1 , Lists),
      Uuid = Record#tb_uchat_message.msgId,
      Id = Record#tb_uchat_message.id,
      ReFrom = Record#tb_uchat_message.from,
      ReTo = Record#tb_uchat_message.to,
      Row = #tb_uchat_message{id = Id , from = ReFrom , to = ReTo , msgId = Uuid , lastTime = Time , lastMessage = LastMessage},
      F = fun() ->
            mnesia:write(Row)
          end,
      mnesia:transaction(F),
      add_tb_uchat_message_record(From , Message , MsgType , Uuid , Time);
    true ->
      Uuid = uuid:uuid_to_string(uuid:get_v4()),
      Id = mnesia:dirty_update_counter(erlang_sequence, tb_uchat_message, 1),
      Row = #tb_uchat_message{id = Id , from = From , to = To , msgId = Uuid , lastTime = Time , lastMessage = LastMessage},
      F = fun() ->
            mnesia:write(Row)
          end,
      mnesia:transaction(F),
      add_tb_uchat_message_record(From , Message , MsgType , Uuid , Time)
  end,
  Val = "user-" ++ binary_to_list(From) ++ "|" ++ binary_to_list(To),
  case ets:member(session , Val) of
    true ->
      ok;
    false ->
      updateMsgUnread(From , To , 9999)
end.

add_tb_uchat_message_record(UserId , Message , MsgType , MsgId , Time) ->
  #{<<"portrait">> := Portrait} = maps:get(<<"responseBody">> , erlchat_user:userInfo(UserId)),
  Id = mnesia:dirty_update_counter(erlang_sequence, tb_uchat_message_record, 1),
  Row = #tb_uchat_message_record{id = Id , userid = UserId , msg = Message , msgType = MsgType , fromAvatar = Portrait , msgId = MsgId , addTime = Time},
  F = fun() ->
        mnesia:write(Row)
      end,
  mnesia:transaction(F).

query_tb_uchat_message(From , To) ->
  do(qlc:q([X || X <- mnesia:table(tb_uchat_message) ,
    ((X#tb_uchat_message.from =:= From) or (X#tb_uchat_message.to =:= From)) and ((X#tb_uchat_message.to =:= To) or (X#tb_uchat_message.from =:= To))])).

%% 更新未读信息
updateMsgUnread(FromUserId , ToUserId , N) ->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message_read) ,
    (X#tb_uchat_message_read.from =:= FromUserId) and (X#tb_uchat_message_read.to =:= ToUserId)])),

  if length(Lists) =:= 1 ->
        Record = lists:nth(1 , Lists),
        Id = Record#tb_uchat_message_read.id,
        Num = erlang:min(Record#tb_uchat_message_read.num , N),
        updateTable(#tb_uchat_message_read{id = Id , from = FromUserId , to = ToUserId , num = Num + 1});
    true ->
        Id = mnesia:dirty_update_counter(erlang_sequence, tb_uchat_message_read, 1),
        updateTable(#tb_uchat_message_read{id = Id , from = FromUserId , to = ToUserId , num = 0})
  end.

totalUnread(UserId) ->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message_read) ,
    (X#tb_uchat_message_read.to =:= UserId)])),
  sum(Lists).

sum([H|T]) -> (H#tb_uchat_message_read.num + sum(T));
sum([]) -> 0.

unReadMsgNum(UserId , FromUserId , ToUserId) ->
  if UserId =:= FromUserId ->
    Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message_read) ,
      ((X#tb_uchat_message_read.from =:= ToUserId) and (X#tb_uchat_message_read.to =:= UserId))])),
    if length(Lists) > 0 ->
       sum(Lists);
       true -> 0
    end;
  true ->
    Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message_read) ,
      ((X#tb_uchat_message_read.from =:= FromUserId) and (X#tb_uchat_message_read.to =:= UserId))])),
    if length(Lists) > 0 ->
       sum(Lists);
       true -> 0
    end
  end.

%% 更新表
updateTable(Map) ->
  F = fun()->
        mnesia:write(Map)
      end,
  mnesia:transaction(F).

%% 创建表
createTable() ->
  mnesia:delete_table(tb_uchat_message),
  mnesia:delete_table(tb_uchat_message_record),
  mnesia:delete_table(tb_uchat_message_read),
  mnesia:create_table(erlang_sequence, [{attributes, record_info(fields,
    erlang_sequence)} , {type,set}, {disc_copies, [node()]}]),
  mnesia:create_table(tb_uchat_message , [{disc_only_copies, [node()]} , {attributes , record_info(fields , tb_uchat_message)}]),
  mnesia:create_table(tb_uchat_message_record , [{disc_only_copies, [node()]} , {attributes , record_info(fields , tb_uchat_message_record)}]),
  mnesia:create_table(tb_uchat_message_read , [{disc_only_copies, [node()]} , {attributes , record_info(fields , tb_uchat_message_read)}]).