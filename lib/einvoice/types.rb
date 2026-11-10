# frozen_string_literal: true

module Einvoice
  # Provider-agnostic domain model for Taiwan e-invoices (財政部 MIG 4.0).
  #
  # Every adapter maps these unified types to/from its own wire format; business
  # code depends ONLY on these so switching providers never touches application
  # logic. All value objects are immutable ({Data}) — use +#with+ to derive a
  # changed copy, and pattern-match via +deconstruct_keys+.
  #
  # Money convention: the statutory amount fields are integers in New Taiwan
  # Dollars (a MIG invariant — even cross-border invoices are filed in TWD). For
  # a foreign-currency sale, set +currency+ (ISO 4217) + +exchange_rate+ to
  # annotate the original transaction; the amount fields stay TWD.

  # 課稅別 — maps to MIG TaxType.
  module TaxType
    TAXABLE    = :taxable      # 應稅 (5% business tax)
    ZERO_RATED = :zero_rated   # 零稅率 (exports etc.)
    TAX_FREE   = :tax_free     # 免稅
    SPECIAL    = :special      # 特種稅額
    ALL = [TAXABLE, ZERO_RATED, TAX_FREE, SPECIAL].freeze
    # Not a MIG tax type, and an issue input does not take it. It describes an
    # existing invoice whose items have different tax types, on a reference or
    # an allowance. Each allowance item then has to carry its own tax_type.
    MIXED = :mixed
    # Taxes that add tax to a line. ZERO_RATED and TAX_FREE lines have tax 0.
    TAXED = [TAXABLE, SPECIAL].freeze

    module_function

    # The tax type of a whole invoice: the one its items share, else MIXED.
    def of(items, invoice_tax_type)
      kinds = items.map { |item| item.tax_type || invoice_tax_type }.uniq
      kinds.size > 1 ? MIXED : kinds.first || invoice_tax_type
    end
  end

  # Invoice category. Derived from whether the buyer has a 統一編號:
  # B2B = triplicate (三聯式), B2C = duplicate (二聯式).
  module InvoiceCategory
    B2B = :b2b
    B2C = :b2c
    ALL = [B2B, B2C].freeze
  end

  # Whether item/line amounts already include the 5% business tax.
  module PriceMode
    TAX_INCLUSIVE = :tax_inclusive
    TAX_EXCLUSIVE = :tax_exclusive
    ALL = [TAX_INCLUSIVE, TAX_EXCLUSIVE].freeze
  end

  # 載具類別.
  module CarrierType
    MOBILE_BARCODE      = :mobile_barcode       # 手機條碼 — /ABC1234 (MIG 3J0002)
    CITIZEN_CERTIFICATE = :citizen_certificate  # 自然人憑證條碼 — 16 chars (MIG CQ0001)
    MEMBER              = :member               # 會員/通用載具 issued by the center
    ALL = [MOBILE_BARCODE, CITIZEN_CERTIFICATE, MEMBER].freeze
  end

  # Lifecycle status of an invoice as reported by a provider.
  module InvoiceStatus
    ISSUED    = :issued
    VOIDED    = :voided
    ALLOWANCE = :allowance  # has at least one active allowance (折讓)
    ALL = [ISSUED, VOIDED, ALLOWANCE].freeze
  end

  module ProviderMode
    TEST       = :test
    PRODUCTION = :production
    ALL = [TEST, PRODUCTION].freeze
  end

  # 買受人. A ubn (統一編號, 8 digits) implies a B2B / triplicate invoice.
  Buyer = Data.define(:name, :ubn, :email, :address, :phone) do
    def initialize(name: nil, ubn: nil, email: nil, address: nil, phone: nil)
      super
    end

    # Presence of a 統一編號 implies a business (B2B) buyer.
    def business?
      !(ubn.nil? || ubn.to_s.empty?)
    end
  end

  # 載具. +code+ shape depends on +type+ (mobile barcode "/"+7, citizen cert 16
  # chars, member often omitted — provider links by email/member id).
  Carrier = Data.define(:type, :code) do
    def initialize(type:, code: nil)
      super
    end
  end

  # 捐贈 — donating the invoice to a charity by 愛心碼.
  Donation = Data.define(:npoban)

  # 愛心碼 are 3–7 digits (MIG 捐贈碼). The single definition of that shape:
  # {Input} enforces it on the way in, and both the adapters and
  # {MOF::DonationCodes} refer to it rather than restating the pattern.
  #
  # Assigned here rather than inside a +Data.define+ block, where a constant
  # would land in +Einvoice+ instead of on this class — the block is evaluated
  # with the enclosing lexical scope, so +Donation::CODE_FORMAT+ would not exist.
  Donation::CODE_FORMAT = /\A\d{3,7}\z/

  # A single invoice line. +tax_type+ is required only on mixed-tax invoices.
  # +unit_price+ and +amount+ include tax or not as the input's +price_mode+
  # says. The core never changes them: the tax of each line is in the input's
  # #tax_breakdown.
  InvoiceItem = Data.define(:description, :quantity, :unit_price, :amount, :unit, :tax_type, :remark) do
    def initialize(description:, quantity:, unit_price:, amount:, unit: nil, tax_type: nil, remark: nil)
      super
    end
  end

  # Monetary summary for the whole invoice (integer TWD).
  # total_amount = sales_amount + tax_amount.
  AmountSummary = Data.define(:sales_amount, :tax_amount, :total_amount)

  # --- Issue (開立) ---

  IssueInvoiceInput = Data.define(
    :order_id, :buyer, :items, :amount, :tax_type, :price_mode, :tax_rate, :category,
    :carrier, :donation, :remark, :currency, :exchange_rate, :provider_options
  ) do
    def initialize(order_id:, buyer:, items:, amount:, tax_type:, price_mode:, tax_rate: nil,
                   category: nil, carrier: nil, donation: nil, remark: nil, currency: nil,
                   exchange_rate: nil, provider_options: nil)
      super
    end

    # Explicit +category+, else derived from the buyer's 統一編號.
    def resolved_category
      category || (buyer&.business? ? InvoiceCategory::B2B : InvoiceCategory::B2C)
    end

    # The tax of every line and the MIG totals, computed by the core. See
    # {TaxBreakdown}.
    def tax_breakdown(provider: nil)
      TaxSplit.breakdown(items, tax_type: tax_type, tax_rate: tax_rate, price_mode: price_mode, provider: provider)
    end
  end

  # --- References ---

  # The facts about an existing invoice that providers ask for when they void,
  # credit or query it. Results of issue and query return one as #reference, so
  # a caller passes it on and does not have to know what each provider needs.
  # Every field is optional. An adapter that needs a missing field may query the
  # provider for it, or raises ValidationError naming the field.
  #
  # +invoice_datetime+ is a Time in UTC+8. +buyer_ubn+ is nil for a consumer.
  # +tax_type+ and +tax_rate+ are the invoice's, so an allowance can take them
  # from here. +tax_type+ is MIXED when the items differ.
  #
  # A reference is stored between calls, often for days. #to_h is that stored
  # form: JSON-safe values only, with +invoice_datetime+ as an ISO 8601 string in
  # UTC+8. Pass the Hash back as +invoice:+, as it is or after a JSON round
  # trip, and Input reads the same reference.
  InvoiceReference = Data.define(:number, :invoice_datetime, :random_code, :order_id, :total_amount,
                                 :buyer_ubn, :tax_type, :tax_rate) do
    def initialize(number: nil, invoice_datetime: nil, random_code: nil, order_id: nil,
                   total_amount: nil, buyer_ubn: nil, tax_type: nil, tax_rate: nil)
      super
    end

    def to_h
      super.merge(invoice_datetime: invoice_datetime && Taipei.iso8601(invoice_datetime),
                  tax_type: tax_type&.to_s, tax_rate: tax_rate && Number.plain(tax_rate.to_r)).compact
    end
  end

  # The facts about an existing allowance. +allowance_date+ is a Date. #to_h is
  # the stored form, as for InvoiceReference, with the date as YYYY-MM-DD.
  AllowanceReference = Data.define(:allowance_number, :allowance_date, :invoice_number) do
    def initialize(allowance_number:, allowance_date: nil, invoice_number: nil)
      super
    end

    def to_h
      super.merge(allowance_date: allowance_date&.strftime("%Y-%m-%d")).compact
    end
  end

  # --- Issue results ---

  # +invoice_datetime+ is a Time in UTC+8 (MIG InvoiceDate and InvoiceTime).
  # +buyer_ubn+ is nil for a consumer. +tax_type+ is TaxType.of the input, so
  # MIXED for a mixed-tax invoice, and +tax_rate+ is the input's rate.
  IssueInvoiceResult = Data.define(
    :invoice_number, :invoice_datetime, :random_code, :order_id, :total_amount, :buyer_ubn, :tax_type,
    :tax_rate, :status, :raw
  ) do
    include Redaction::Raw

    def reference
      InvoiceReference.new(number: invoice_number, invoice_datetime: invoice_datetime,
                           random_code: random_code, order_id: order_id,
                           total_amount: total_amount, buyer_ubn: buyer_ubn,
                           tax_type: tax_type, tax_rate: tax_rate)
    end
  end

  # --- Void (作廢) ---

  # +invoice+ is an InvoiceReference (Input also takes a plain number).
  VoidInvoiceInput = Data.define(:invoice, :reason, :provider_options) do
    def initialize(invoice:, reason:, provider_options: nil)
      super
    end
  end

  # +cancel_datetime+ is a Time in UTC+8 (MIG CancelDate and CancelTime), or nil
  # when the provider does not return it.
  VoidInvoiceResult = Data.define(:invoice_number, :status, :cancel_datetime, :raw) do
    include Redaction::Raw

    def initialize(invoice_number:, status:, raw:, cancel_datetime: nil)
      super
    end
  end

  # --- Allowance (折讓) and its cancellation (折讓作廢) ---

  # +price_mode+ says if the item amounts include tax. +tax_type+ and
  # +tax_rate+ come from the input, else from the invoice reference. With a
  # MIXED tax type, every item carries its own tax_type.
  #
  # +amount+ follows G0401: +sales_amount+ excludes tax. Input checks it
  # against #tax_breakdown, which holds the tax of each line.
  AllowanceInput = Data.define(:invoice, :allowance_id, :items, :amount, :price_mode, :tax_type, :tax_rate,
                               :provider_options) do
    def initialize(invoice:, allowance_id:, items:, amount:, price_mode:, tax_type:, tax_rate:,
                   provider_options: nil)
      super
    end

    def tax_breakdown(provider: nil)
      TaxSplit.breakdown(items, tax_type: tax_type, tax_rate: tax_rate, price_mode: price_mode, provider: provider)
    end
  end

  # +allowance_date+ is a Date (MIG AllowanceDate has no time).
  AllowanceResult = Data.define(:allowance_number, :invoice_number, :allowance_date, :total_amount, :raw) do
    include Redaction::Raw

    def reference
      AllowanceReference.new(allowance_number: allowance_number, allowance_date: allowance_date,
                             invoice_number: invoice_number)
    end
  end

  # +allowance+ is an AllowanceReference (Input also takes a plain number).
  VoidAllowanceInput = Data.define(:allowance, :reason, :provider_options) do
    def initialize(allowance:, reason: nil, provider_options: nil)
      super
    end
  end

  VoidAllowanceResult = Data.define(:allowance_number, :cancel_datetime, :raw) do
    include Redaction::Raw

    def initialize(allowance_number:, raw:, cancel_datetime: nil)
      super
    end
  end

  # --- Query (查詢) ---

  # +invoice+ is an InvoiceReference with a number or an order id. A reference
  # with only an order id (and what the provider needs with it) finds an invoice
  # without its number. That needs QUERY_BY_ORDER_ID.
  QueryInvoiceInput = Data.define(:invoice, :provider_options) do
    def initialize(invoice:, provider_options: nil)
      super
    end
  end

  # +status+ is nil when the provider's status has no InvoiceStatus, for
  # example a cancelled (註銷) invoice.
  #
  # +tax_type+ and +tax_rate+ are nil when the provider does not say.
  QueryInvoiceResult = Data.define(
    :invoice_number, :invoice_datetime, :random_code, :order_id, :status, :amount, :buyer, :items, :tax_type,
    :tax_rate, :raw
  ) do
    include Redaction::Raw

    def reference
      InvoiceReference.new(number: invoice_number, invoice_datetime: invoice_datetime,
                           random_code: random_code, order_id: order_id,
                           total_amount: amount&.total_amount, buyer_ubn: buyer&.ubn,
                           tax_type: tax_type, tax_rate: tax_rate)
    end
  end
end
