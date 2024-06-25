import gleam/erlang/process.{type ProcessMonitor, type Selector, type Subject}
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
  SubscriberDown(process.ProcessDown)
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
  Subscriber(client: Subject(m), monitor: ProcessMonitor)
}

const timeout = 1000

/// Creates a new topic. Which is a pubsub channel that clients can subscribe to.
pub fn new_topic() -> Result(Topic(m), GlubsubError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let selector = process.new_selector()
      actor.Ready(State(subscribers: [], selector: selector), selector)
    },
    init_timeout: timeout,
    loop: handle_message,
  ))
  |> result.map(fn(subject) { Topic(subject) })
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
pub fn get_subscribers(topic: Topic(m)) -> List(Subscriber(m)) {
  actor.call(topic_to_subject(topic), GetSubscribers, timeout)
}

fn handle_message(
  message: Message(m),
  state: State(m),
) -> actor.Next(Message(m), State(m)) {
  case message {
    Subscribe(reply, client) -> {
      case list.find(state.subscribers, fn(sub) { sub.client == client }) {
        Ok(_) -> {
          actor.send(reply, Error(AlreadySubscribed))
          actor.continue(state)
        }
        Error(Nil) -> {
          let monitor = process.monitor_process(process.subject_owner(client))
          let new_selector =
            state.selector
            |> process.selecting_process_down(monitor, SubscriberDown)

          let new_subs = [
            Subscriber(client: client, monitor: monitor),
            ..state.subscribers
          ]

          actor.send(reply, Ok(Nil))
          actor.continue(State(subscribers: new_subs, selector: new_selector))
          |> actor.with_selector(new_selector)
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

          let new_selector =
            process.new_selector()
            |> selector_down_from_subscribers(new_subs)

          actor.send(reply, Ok(Nil))
          actor.continue(State(subscribers: new_subs, selector: new_selector))
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
    SubscriberDown(client) -> {
      case
        state.subscribers
        |> list.find(fn(sub) { process.subject_owner(sub.client) == client.pid })
      {
        Error(Nil) -> {
          actor.continue(state)
        }
        Ok(unsub) -> {
          process.demonitor_process(unsub.monitor)
          let new_subs = remove_subscriber(state.subscribers, unsub)

          let new_selector =
            process.new_selector()
            |> selector_down_from_subscribers(new_subs)

          actor.continue(State(subscribers: new_subs, selector: new_selector))
        }
      }
    }
    Shutdown -> {
      actor.Stop(process.Normal)
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
  subscribers
  |> list.pop(fn(sub) { sub == unsubscriber })
  |> result.map(fn(res) { res.1 })
  |> result.unwrap(subscribers)
}

fn selector_down_from_subscribers(
  selector: Selector(Message(m)),
  subscribers: List(Subscriber(m)),
) -> Selector(Message(m)) {
  list.fold(subscribers, selector, fn(selector, sub) {
    process.selecting_process_down(selector, sub.monitor, SubscriberDown)
  })
}
