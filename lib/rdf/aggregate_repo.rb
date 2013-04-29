require 'rdf'

module RDF
  autoload :MergeGraph, 'rdf/aggregate_repo/merge_graph'
  autoload :VERSION, 'rdf/aggregate_repo/version'

  ##
  # An aggregated RDF repository.
  #
  # Aggregates the default and named graphs from one or more instances
  # implementing RDF::Queryable. By default, the aggregate projects
  # no default or named graphs, which must be added explicitly.
  #
  # Adding the existing default graph (identified with the name `false`)
  # adds the merge of all default graphs from the specified `queryable`
  # instances.
  #
  # Adding a named graph, adds the last graph found having that name
  # from the specified `queryable` instances.
  #
  # Updating a previously non-existing named graph, appends to the last source. Updating the default graph updates to the merge of the graphs.
  #
  # @example Constructing an aggregate with arguments
  #   aggregate = RDF::AggregateRepo.new(repo1, repo2)
  #
  # @example Constructing an aggregate with closure
  #   aggregate = RDF::AggregateRepo.new do
  #     source repo1
  #     source repo2
  #     default false
  #     named   RDF::URI("http://example/")
  #     named   RDF::URI("http://other/")
  #   end
  #
  # @todo Allow graph names to reassigned with queryable
  class AggregateRepo < RDF::Repository
    ##
    # The set of aggregated `queryable` instances included in this aggregate
    #
    # @return [Array<RDF::Queryable>]
    attr_reader :sources

    ##
    # Names of the named graphs making up the default graph, or
    # false, if it is made up from the merger of all default
    # graphs
    #
    # @return [Array<RDF::URI, false>]
    attr_reader :defaults

    ##
    # Create a new aggregation instance.
    #
    # @overload initialize(queryable = [], options = {})
    #   @param [Array<RDF::Queryable>] queryable ([])
    #   @param [Hash{Symbol => Object}] options ({})
    #   @yield aggregation
    #   @yieldparam [RDF::AggregateRepo] aggregation
    #   @yieldreturn [void] ignored
    def initialize(*queryable, &block)
      @options = queryable.last.is_a?(Hash) ? queryable.last.dup : {}
      
      @sources = queryable
      @defaults = []
      @contexts = []

      if block_given?
        case block.arity
        when 1 then block.call(self)
        else instance_eval(&block)
        end
      end
    end

    ##
    # Add a queryable to the set of constituent queryable instances
    #
    # @param [RDF::Queryable] queryable
    # @return [RDF::AggregateRepo] self
    def source(queryable)
      @sources << queryable
      @default_graph = nil
      self
    end
    alias_method :add, :source

    ##
    # Set the default graph based on zero or more
    # named graphs, or the merge of all default graphs if `false`
    #
    # @param [Array<RDF::Resource>, false] names
    # @return [RDF::AggregateRepo] self
    def default(*names)
      if names.any? {|n| n == false} && names.length > 1
        raise ArgumentError, "If using merge of default graphs, there can be only one"
      end
      @default_graph = nil
      @defaults = names
    end

    ##
    # Add a named graph projection. Dynamically binds to the
    # last `queryable` having a matching context.
    #
    # @param [RDF::Resource] name
    # @return [RDF::AggregateRepo] self
    def named(name)
      raise ArgumentError, "name must be an RDF::Resource: #{name.inspect}" unless name.is_a?(RDF::Resource)
      raise ArgumentError, "name does not exist in loaded sources" unless sources.any?{|s| s.has_context?(name)}
      @contexts << name
    end

    # Repository overrides

    ##
    # Not writable
    #
    # @return [false]
    def writable?; false; end

    ##
    # Returns `true` all constituent graphs are durable.
    #
    # @return [Boolean]
    # @see RDF::Durable#durable?
    def durable?
      sources.all?(&:durable?)
    end

    ##
    # Returns `true` if all constituent graphs are empty.
    #
    # @return [Boolean]
    # @see RDF::Countable#empty?
    def empty?
      count == 0
    end

    ##
    # Returns the number of RDF statements in all constituent graphs.
    #
    # @return [Integer]
    # @see RDF::Countable#count
    def count
      each_graph.to_a.reduce(0) {|memo, g| memo += g.count}
    end

    ##
    # Returns `true` if any constituent graph contains the given RDF statement.
    #
    # @param  [RDF::Statement] statement
    # @return [Boolean]
    # @see RDF::Enumerable#has_statement?
    def has_statement?(statement)
      each_graph.to_a.any? {|g| g.has_statement?(statement)}
    end

    ##
    # Iterates the given block for each RDF statement.
    #
    # If no block was given, returns an enumerator.
    #
    # The order in which statements are yielded is undefined.
    #
    # @overload each_statement
    #   @yield  [statement]
    #     each statement
    #   @yieldparam  [RDF::Statement] statement
    #   @yieldreturn [void] ignored
    #   @return [void]
    #
    # @overload each_statement
    #   @return [Enumerator]
    #
    # @return [void]
    # @see RDF::Repository#each_statement
    # @see RDF::Enumerable#each_statement
    def each_statement(&block)
      if block_given?
        # Invoke {#each} in the containing class:
        each(&block)
      end
      enum_statement
    end

    ##
    # Enumerates each RDF statement in constituent graphs
    #
    # @yield  [statement]
    # @yieldparam [Statement] statement
    # @return [Enumerator]
    # @see RDF::Enumerable#each
    def each(&block)
      return to_enum unless block_given?
      each_graph {|g| g.each(&block)}
    end

    ##
    # Returns `true` if any constituent grahp contains the given RDF context.
    #
    # @param  [RDF::Resource, false] value
    #   Use value `false` to query for the default context
    # @return [Boolean]
    # @see RDF::Enumerable#has_context?
    def has_context?(value)
      @contexts.include?(value)
    end

    ##
    # Iterates the given block for each unique RDF context, other than the default context.
    #
    # If no block was given, returns an enumerator.
    #
    # The order in which values are yielded is undefined.
    #
    # @overload each_context
    #   @yield  [context]
    #     each context term
    #   @yieldparam  [RDF::Resource] context
    #   @yieldreturn [void] ignored
    #   @return [void]
    #
    # @overload each_context
    #   @return [Enumerator]
    #
    # @return [void]
    # @see RDF::Enumerable#each_context
    def each_context(&block)
      if block_given?
        @contexts.each(&block)
      end
      enum_context
    end


    ##
    # Iterate over each graph, in order, finding named graphs from the most recently added `source`.
    #
    # If no block was given, returns an enumerator.
    #
    # The order in which graphs are yielded is undefined.
    #
    # @overload each_graph
    #   @yield  [graph]
    #     each graph
    #   @yieldparam  [RDF::Graph] graph
    #   @yieldreturn [void] ignored
    #   @return [void]
    #
    # @overload each_graph
    #   @return [Enumerator]
    #
    # @return [void]
    # @see RDF::Enumerable#each_graph
    def each_graph(&block)
      if block_given?
        block.call(default_graph)

        # Send context from appropriate source
        each_context do |context|
          source  = sources.reverse.detect {|s| s.has_context?(context)}
          block.call(RDF::Graph.new(context, :data => source))
        end
      end
      enum_graph
    end

  protected

    ##
    # Queries each constituent graph for RDF statements matching the given `pattern`,
    # yielding each matched statement to the given block.
    #
    # @param  [RDF::Query::Pattern] pattern
    #   the query pattern to match
    # @yield  [statement]
    # @yieldparam  [RDF::Statement] statement
    # @yieldreturn [void] ignored
    # @return [void] ignored
    # @see RDF::Queryable#query_pattern
    def query_pattern(pattern, &block)
      case pattern.context
      when nil
        # Query against all graphs
        each_graph {|graph| graph.send(:query_pattern, pattern, &block)}
      when FalseClass
        # Query against default graph only
        default_graph.send(:query_pattern, pattern, &block)
      when RDF::Query::Variable
        # Query against all named graphs
        each_context do |context|
          source  = sources.reverse.detect {|s| s.has_context?(context)}
          RDF::Graph.new(context, :data => source).send(:query_pattern, pattern, &block)
        end
      else
        # Query against a specific context
        if @contexts.include?(pattern.context)
          source  = sources.reverse.detect {|s| s.has_context?(pattern.context)}
          RDF::Graph.new(pattern.context, :data => source).send(:query_pattern, pattern, &block)
        end
      end
    end

    ##
    # Default graph of this aggregate, either a projection of the source
    # default graph (if `false`), a particular named graph from the
    # last source in which it appears, or a MergeGraph composed of the
    # graphs which compose it.
    #
    # @return [RDF::Graph]
    def default_graph
      @default_graph ||= begin
        case
        when sources.length == 0 || defaults.length == 0
          RDF::Graph.new
        when defaults.length == 1 && sources.length == 1
          RDF::Graph.new((defaults.first || nil), :data => sources.first)
        else
          # Otherwise, create a MergeGraph from the set of pairs of source and context
          RDF::MergeGraph.new(:name => nil) do
            if defaults == [false]
              sources.each do |s|
                # Add default graph from each source
                source s, false
              end
            else
              each_context do |context|
                # add the named graph
                source sources.reverse.detect {|s| s.has_context?(context)}, context
              end
            end
          end
        end
      end
    end
  end
end