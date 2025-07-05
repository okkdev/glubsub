//// This module implements a simple pubsub system using gleam actors.
////

import gleam/erlang/process.{type Monitor, type Selector, type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result

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
  GetSubscribers(reply_with: Subject(List(Subscriber(m))))
  SubscriberDown(process.Down)
  Shutdown
}

pub opaque type GlubsubError {
  AlreadySubscribed
  NotSubscribed
  StartError(actor.StartError)
}

type State(m) {
  State(subscribers: List(Subscriber(m)), selector: Selector(Message(m)))
}

pub type Subscriber(m) {
  Subscriber(client: Subject(m), monitor: Monitor)
}

const timeout = 1000

/// Creates a new topic. Which is a pubsub channel that clients can subscribe to.
pub fn new_topic() -> Result(Topic(m), GlubsubError) {
  actor.new_with_initialiser(timeout, fn(subject) {
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> process.select_monitors(SubscriberDown)
    actor.initialised(State(subscribers: [], selector: selector))
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok()
  })
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) {
    let actor.Started(data: subject, ..) = started
    Topic(subject)
  })
  |> result.map_error(fn(err) { StartError(err) })
}

/// Destroys the given topic, unsubscribing all clients.
pub fn destroy_topic(topic: Topic(m)) -> Nil {
  actor.send(topic_to_subject(topic), Shutdown)
}

/// Subscribes the given client to the given topic.
pub fn subscribe(
  topic: Topic(m),
  client: Subject(m),
) -> Result(Nil, GlubsubError) {
  actor.call(topic_to_subject(topic), timeout, fn(self) {
    Subscribe(self, client)
  })
}

/// Unsubscribes the given client from the given topic.
pub fn unsubscribe(
  topic: Topic(m),
  client: Subject(m),
) -> Result(Nil, GlubsubError) {
  actor.call(topic_to_subject(topic), timeout, fn(self) {
    Unsubscribe(self, client)
  })
}

/// Broadcasts a message to all subscribers of the given topic.
pub fn broadcast(topic: Topic(m), message: m) -> Result(Nil, Nil) {
  actor.send(topic_to_subject(topic), Broadcast(message))
  |> Ok
}

/// Returns a set of all subscribers to the given topic.
pub fn get_subscribers(topic: Topic(m)) -> List(Subscriber(m)) {
  actor.call(topic_to_subject(topic), timeout, GetSubscribers)
}

fn handle_message(
  state: State(m),
  message: Message(m),
) -> actor.Next(State(m), Message(m)) {
  case message {
    Subscribe(reply, client) -> {
      case list.find(state.subscribers, fn(sub) { sub.client == client }) {
        Ok(_) -> {
          actor.send(reply, Error(AlreadySubscribed))
          actor.continue(state)
        }
        Error(Nil) -> {
          case process.subject_owner(client) {
            Ok(pid) -> {
              let monitor = process.monitor(pid)

              let new_subs = [
                Subscriber(client: client, monitor: monitor),
                ..state.subscribers
              ]

              actor.send(reply, Ok(Nil))
              actor.continue(State(..state, subscribers: new_subs))
            }
            Error(_) -> {
              // Subject was for a named process which has died between calling
              // us and us trying to monitor them -> ignore
              actor.continue(state)
            }
          }
        }
      }
    }
    Unsubscribe(reply, client) -> {
      case list.find(state.subscribers, fn(sub) { sub.client == client }) {
        Error(Nil) -> {
          actor.send(reply, Error(NotSubscribed))
          actor.continue(state)
        }
        Ok(unsub) -> {
          let new_subs = remove_subscriber(state.subscribers, unsub)

          actor.send(reply, Ok(Nil))
          actor.continue(State(..state, subscribers: new_subs))
        }
      }
    }
    Broadcast(message) -> {
      state.subscribers
      |> list.each(fn(sub) { actor.send(sub.client, message) })
      actor.continue(state)
    }
    GetSubscribers(reply) -> {
      actor.send(reply, state.subscribers)
      actor.continue(state)
    }
    SubscriberDown(process.ProcessDown(pid:, ..)) -> {
      let ok_pid = Ok(pid)
      case
        state.subscribers
        |> list.find(fn(sub) { process.subject_owner(sub.client) == ok_pid })
      {
        Error(Nil) -> {
          actor.continue(state)
        }
        Ok(unsub) -> {
          process.demonitor_process(unsub.monitor)
          let new_subs = remove_subscriber(state.subscribers, unsub)

          actor.continue(State(..state, subscribers: new_subs))
        }
      }
    }
    // A monitored port is down, which should never happen -> ignore
    SubscriberDown(_) -> actor.continue(state)
    Shutdown -> {
      actor.stop()
    }
  }
}

fn topic_to_subject(topic: Topic(m)) -> Subject(Message(m)) {
  let Topic(subject) = topic
  subject
}

fn remove_subscriber(
  subscribers: List(Subscriber(m)),
  unsubscriber: Subscriber(m),
) -> List(Subscriber(m)) {
  list.filter(subscribers, fn(sub) { sub != unsubscriber })
}
