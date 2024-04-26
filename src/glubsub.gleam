import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/set.{type Set}

pub opaque type Message(m) {
  Subscribe(reply_with: Subject(Result(Nil, GlubsubError)), client: Subject(m))
  Unsubscribe(
    reply_with: Subject(Result(Nil, GlubsubError)),
    client: Subject(m),
  )
  Broadcast(message: m)
  GetSubscribers(reply_with: Subject(Set(Subject(m))))
}

pub type GlubsubError {
  AlreadySubscribed
  NotSubscribed
}

pub fn new() -> Result(Subject(Message(m)), actor.StartError) {
  actor.start(set.new(), handle_message)
}

pub fn subscribe(
  topic: Subject(Message(m)),
  client: Subject(m),
) -> Result(Nil, GlubsubError) {
  actor.call(topic, fn(self) { Subscribe(self, client) }, 100)
}

pub fn unsubscribe(
  topic: Subject(Message(m)),
  client: Subject(m),
) -> Result(Nil, GlubsubError) {
  actor.call(topic, fn(self) { Unsubscribe(self, client) }, 100)
}

pub fn broadcast(topic: Subject(Message(m)), message: m) -> Result(Nil, Nil) {
  actor.send(topic, Broadcast(message))
  |> Ok
}

@internal
pub fn get_subscribers(topic: Subject(Message(m))) -> Set(Subject(m)) {
  actor.call(topic, GetSubscribers, 100)
}

fn handle_message(
  message: Message(m),
  subs: Set(Subject(m)),
) -> actor.Next(a, Set(Subject(m))) {
  case message {
    Subscribe(reply, client) -> {
      case set.contains(subs, client) {
        True -> {
          actor.send(reply, Error(AlreadySubscribed))
          actor.continue(subs)
        }
        False -> {
          let new_subs = set.insert(subs, client)
          actor.send(reply, Ok(Nil))
          actor.continue(new_subs)
        }
      }
    }
    Unsubscribe(reply, client) -> {
      case set.contains(subs, client) {
        False -> {
          actor.send(reply, Error(NotSubscribed))
          actor.continue(subs)
        }
        True -> {
          let new_subs = set.delete(subs, client)
          actor.send(reply, Ok(Nil))
          actor.continue(new_subs)
        }
      }
    }
    Broadcast(message) -> {
      set.to_list(subs)
      |> list.each(fn(subscriber) { actor.send(subscriber, message) })
      actor.continue(subs)
    }
    GetSubscribers(reply) -> {
      actor.send(reply, subs)
      actor.continue(subs)
    }
  }
}
