# frozen_string_literal: true

# Reads the error code tables in section 6.4 of a provider note, so a spec can
# hold the code to what the note says. A table row is
#
#   | `code`, `code` or `code` to `code` | Meaning | `XError` | `REASON` |
#
# Rows without a class (a success code, or one the note only describes) and
# rows mapped "(by message)" are left out: they are not in the code table.
module NoteErrorTable
  Row = Data.define(:codes, :error_class, :reason)

  module_function

  # Each documented code whose mapping differs from the note, as
  # "code: note [class, reason], code [class, reason]". Empty when they agree.
  def mismatches(rows)
    rows.flat_map do |row|
      expected = [row.error_class::CODE, row.reason]
      row.codes.filter_map do |code|
        actual = yield(code)
        "#{code}: note #{expected.inspect}, code #{actual.inspect}" unless actual == expected
      end
    end
  end

  # The tables of section 6.4, in order. Each is an Array of Rows.
  def tables(note)
    path = File.expand_path("../../docs/providers/#{note}", __dir__)
    section = File.read(path)[/^### 6\.4 .*?(?=^## )/m] or raise "#{note}: no section 6.4"
    section.split(/\n(?=\| Code )/).drop(1).map do |table|
      table.lines.grep(/\A\| `/).filter_map { |line| row(line) }
    end
  end

  def row(line)
    code_cell, _meaning, class_cell, reason_cell = line.split("|").map(&:strip).reject(&:empty?)
    error_class = class_cell.to_s[/\A`(\w+Error)`\z/, 1]
    return unless error_class

    reason = reason_cell.to_s[/\A`([A-Z_]+)`\z/, 1]
    Row.new(codes: codes(code_cell), error_class: Einvoice.const_get(error_class),
            reason: reason && Einvoice::Reason.const_get(reason))
  end

  def codes(cell)
    if (range = cell.match(/\A`(\d+)` to `(\d+)`\z/))
      (range[1].to_i..range[2].to_i).map(&:to_s)
    else
      cell.scan(/`([^`]+)`/).flatten
    end
  end
end
