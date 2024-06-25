# glubsub

tiny pubsub inspired abstraction.

[![Package Version](https://img.shields.io/hexpm/v/glubsub)](https://hex.pm/packages/glubsub)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glubsub/)

```sh
gleam add glubsub
```

```gleam
import gleam/otp/actor
import gleam/io
import glubsub

type Message {
  Broadcast(String)
}

pub fn main() {
  let assert Ok(topic) = glubsub.new_topic()

  let assert Ok(actor) = actor.start(Nil, handle_message)

  glubsub.subscribe(topic, actor)

  glubsub.broadcast(topic, Broadcast("Hello Wobble!"))
}

fn handle_message(message: Message, state) -> actor.Next(a, Nil) {
  case message {
    Broadcast(msg) -> {
      io.println(msg)
      actor.continue(state)
    }
  }
}
```

## Development

```sh
gleam test  # Run the tests
```
