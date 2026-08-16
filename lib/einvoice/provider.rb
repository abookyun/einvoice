# frozen_string_literal: true

module Einvoice
  # The contract every provider adapter implements. Application code depends on
  # this base, never on a concrete adapter, so providers are swappable — switching
  # is a one-line constructor change.
  #
  # All five operations raise an {Einvoice::Error} on failure. Subclasses must
  # implement {#name}, {#capabilities}, and the five operations; {#supports?} and
  # {#assert_supports!} come from {Capability::Support}.
  class Provider
    include Capability::Support

    # A stable identifier, e.g. "amego", "ecpay".
    def name
      raise NotImplementedError, "#{self.class} must implement #name"
    end

    # The set of optional features this adapter declares (a Set of
    # {Capability} symbols).
    def capabilities
      raise NotImplementedError, "#{self.class} must implement #capabilities"
    end

    # 開立發票.
    def issue(_input)
      raise NotImplementedError, "#{self.class} must implement #issue"
    end

    # 作廢發票.
    def void(_input)
      raise NotImplementedError, "#{self.class} must implement #void"
    end

    # 開立折讓.
    def allowance(_input)
      raise NotImplementedError, "#{self.class} must implement #allowance"
    end

    # 作廢折讓.
    def void_allowance(_input)
      raise NotImplementedError, "#{self.class} must implement #void_allowance"
    end

    # 查詢發票.
    def query(_input)
      raise NotImplementedError, "#{self.class} must implement #query"
    end
  end
end
