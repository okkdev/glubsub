import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}

pub type Topic(m) {
  Topic(Subject(Message(m)))
}

pub opaque type Message(m) {
  Subscribe(reply_with: Subject(Result(Nil, GlubsubError)), client: Subject(m))
  Unsubscribe(
    reply_with: Subject(Result(Nil, GlubsubError)),
    client: Subject(m),
  )
  Broadcast(message: m)
  GetSubscribers(reply_with: Subject(Set(Subject(m))))
}

pub opaque type GlubsubError {
  AlreadySubscribed
  NotSubscribed
}

const timeout = 1000

/// Creates a new topic. Which is a pubsub channel that clients can subscribe to.
pub fn new_topic() -> Result(Topic(m), actor.StartError) {
  actor.start(set.new(), handle_message)
  |> result.map(fn(subject) { Topic(subject) })
}

/// Subscribes the given client to the given topic.
pub fn subscribe(
  topic: Topic(m),
  client: Subject(m),
) -> Result(Nil, GlubsubError) {
  actor.call(
    topic_to_subject(topic),
    fn(self) { Subscribe(self, client) },
    timeout,
  )
}

/// Unsubscribes the given client from the given topic.
pub fn unsubscribe(
  topic: Topic(m),
  client: Subject(m),
) -> Result(Nil, GlubsubError) {
  actor.call(
    topic_to_subject(topic),
    fn(self) { Unsubscribe(self, client) },
    timeout,
  )
}

/// Broadcasts a message to all subscribers of the given topic.
pub fn broadcast(topic: Topic(m), message: m) -> Result(Nil, Nil) {
  actor.send(topic_to_subject(topic), Broadcast(message))
  |> Ok
}

/// Returns a set of all subscribers to the given topic.
pub fn get_subscribers(topic: Topic(m)) -> Set(Subject(m)) {
  actor.call(topic_to_subject(topic), GetSubscribers, timeout)
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

fn topic_to_subject(topic: Topic(m)) -> Subject(Message(m)) {
  case topic {
    Topic(subject) -> subject
  }
}
