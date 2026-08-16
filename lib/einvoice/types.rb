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

  # 捐贈 — donating the invoice to a charity by 愛心碼 (3–7 digits).
  Donation = Data.define(:npoban)

  # A single invoice line. +tax_type+ is required only on mixed-tax invoices.
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
    :carrier, :donation, :remark, :currency, :exchange_rate, :date, :provider_options
  ) do
    def initialize(order_id:, buyer:, items:, amount:, tax_type:, price_mode:, tax_rate: nil,
                   category: nil, carrier: nil, donation: nil, remark: nil, currency: nil,
                   exchange_rate: nil, date: nil, provider_options: nil)
      super
    end

    # Explicit +category+, else derived from the buyer's 統一編號.
    def resolved_category
      category || (buyer&.business? ? InvoiceCategory::B2B : InvoiceCategory::B2C)
    end
  end

  IssueInvoiceResult = Data.define(
    :invoice_number, :invoice_date, :random_code, :order_id, :total_amount, :status, :raw
  )

  # --- Void (作廢) ---

  VoidInvoiceInput = Data.define(:invoice_number, :reason, :date, :provider_options) do
    def initialize(invoice_number:, reason:, date: nil, provider_options: nil)
      super
    end
  end

  VoidInvoiceResult = Data.define(:invoice_number, :status, :raw)

  # --- Allowance (折讓) and its cancellation (折讓作廢) ---

  AllowanceInput = Data.define(:invoice_number, :allowance_id, :items, :amount, :date, :provider_options) do
    def initialize(invoice_number:, allowance_id:, items:, amount:, date: nil, provider_options: nil)
      super
    end
  end

  AllowanceResult = Data.define(:allowance_number, :invoice_number, :allowance_date, :total_amount, :raw)

  VoidAllowanceInput = Data.define(:invoice_number, :allowance_number, :reason, :provider_options) do
    def initialize(invoice_number:, allowance_number:, reason: nil, provider_options: nil)
      super
    end
  end

  VoidAllowanceResult = Data.define(:allowance_number, :raw)

  # --- Query (查詢) ---

  # Query by invoice number, or by your order id — at least one required.
  QueryInvoiceInput = Data.define(:invoice_number, :order_id, :provider_options) do
    def initialize(invoice_number: nil, order_id: nil, provider_options: nil)
      super
    end
  end

  QueryInvoiceResult = Data.define(
    :invoice_number, :invoice_date, :random_code, :order_id, :status, :amount, :buyer, :items, :raw
  )
end
