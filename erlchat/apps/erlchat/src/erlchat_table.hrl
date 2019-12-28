%%%-------------------------------------------------------------------
%%% @author fu
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 11. 十一月 2019 17:03
%%%-------------------------------------------------------------------
-author("fu").
%自增索引表，维护其他表的自增id
-record(erlang_sequence, {name, seq}).
-record(tb_uchat_message , {
  id,
  to,
  from,
  msgId,
  lastMessage,
  lastTime,
  lastMsgType
}).

-record(tb_uchat_message_read , {
  id,
  from,
  to,
  num
}).

-record(tb_uchat_message_record , {
  id,
  msgId,
  userid,
  msg,
  msgType,
  addTime,
  fromAvatar,
  isDel
}).

%%关联用户信息,消息,好友信息
-record(tb_uchat_join_message , {
  id,
  fromUserId,
  toUserId,
  lastTime,
  lastMessage,
  lastMsgType,
  toAvatar,
  toName,
  toCompany,
  toPosition,
  fromAvatar,
  fromName,
  fromCompany,
  fromPosition,
  unread,
  tid
}).