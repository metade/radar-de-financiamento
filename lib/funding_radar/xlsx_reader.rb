require "rexml/document"
require "rexml/xpath"
require "stringio"
require "zip"

module FundingRadar
  class XlsxReader
    NAMESPACE = {"x" => "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}.freeze

    def rows(contents)
      archive = Zip::File.open_buffer(StringIO.new(contents))
      begin
        shared_strings = shared_strings_from(archive.read("xl/sharedStrings.xml"))
        sheet = REXML::Document.new(archive.read("xl/worksheets/sheet1.xml"))

        result = REXML::XPath.match(sheet, "//x:sheetData/x:row", NAMESPACE).map do |row|
          cells = {}
          REXML::XPath.match(row, "x:c", NAMESPACE).each do |cell|
            reference = cell.attributes["r"].to_s
            column = reference[/\A[A-Z]+/]
            value = REXML::XPath.first(cell, "x:v", NAMESPACE)&.text
            value = shared_strings[value.to_i] if cell.attributes["t"] == "s" && value
            cells[column] = value
          end
          cells
        end
      ensure
        archive.close
      end
      result
    end

    private

    def shared_strings_from(xml)
      document = REXML::Document.new(xml)
      REXML::XPath.match(document, "//x:si", NAMESPACE).map do |item|
        REXML::XPath.match(item, ".//x:t", NAMESPACE).map(&:text).join
      end
    end
  end
end
