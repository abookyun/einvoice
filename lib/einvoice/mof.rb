# frozen_string_literal: true

require "einvoice/mof/donation_codes"

module Einvoice
  # Direct clients for 財政部's own public services — the authority every
  # value-added center ultimately files to.
  #
  # These are not {Einvoice::Provider}s: they issue nothing, hold no merchant
  # credentials, and are provider-independent, so they work whichever center you
  # issue through (and when you haven't chosen one yet). Everything here is
  # opt-in and called explicitly; nothing on the issue path reaches for it.
  module MOF
  end
end
