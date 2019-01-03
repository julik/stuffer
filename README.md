# stuffer
Evaluating Falcon speed for high-volume data output

# Testing it

```
bundle install
bundle exec falcon serve -b http://localhost:9494
```

then hit your server with `ab`. This will generate _a ton_ of data and _a ton_ of traffic.
But it will show what throughput you can have if you are not dependent on an upstream to
furnish you data.
