# Tolzar CSV exports: a cell a spreadsheet would run as a formula (=, +, -, @, tab, carriage return first) starts
# with a quote instead, so a contact named "=HYPERLINK(...)" stays text in Excel or Sheets.
module Tolzar::CsvCell
  FORMULA = /\A[=+\-@\t\r]/

  def self.safe(value)
    value.to_s.match?(FORMULA) ? "'#{value}" : value
  end
end
