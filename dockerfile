FROM ruby:2.6.3
COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v '2.0.2'
WORKDIR /app
COPY . .
RUN bundle install
CMD ["ruby", "app/simpsons_simulator.rb"]

