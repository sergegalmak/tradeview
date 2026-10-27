import Foundation

public enum PortfolioCSVError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): "CSV: \(message)" }
    }
}

public enum PortfolioCSV {
    /// Strict comma-separated UTF-8 input; quoted fields, escaped quotes and CRLF are supported.
    /// All rows are validated before the caller changes any portfolio state.
    public static func parse(_ text: String) throws -> [PortfolioPosition] {
        guard text.utf8.count <= 1_000_000 else { throw PortfolioCSVError.invalid("размер превышает 1 МБ.") }
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var closedQuote = false
        var iterator = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").makeIterator()
        while let character = iterator.next() {
            if quoted {
                if character == "\"" { quoted = false; closedQuote = true }
                else { field.append(character) }
            } else if character == "\"" {
                if closedQuote { field.append("\""); quoted = true; closedQuote = false }
                else if field.isEmpty { quoted = true }
                else { throw PortfolioCSVError.invalid("кавычка внутри неэкранированного поля.") }
            } else if character == "," || character == "\n" {
                row.append(field); field = ""; closedQuote = false
                if character == "\n" { rows.append(row); row = [] }
            } else {
                guard !closedQuote else { throw PortfolioCSVError.invalid("символ после закрывающей кавычки.") }
                field.append(character)
            }
        }
        guard !quoted else { throw PortfolioCSVError.invalid("незакрытые кавычки.") }
        if !field.isEmpty || !row.isEmpty || closedQuote { row.append(field); rows.append(row) }
        rows.removeAll { $0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = rows.first,
              header.enumerated().map({ index, field in
                  (index == 0 ? field.replacingOccurrences(of: "\u{FEFF}", with: "") : field)
                      .trimmingCharacters(in: .whitespaces).lowercased()
              }) == ["ticker", "shares", "average_cost"] else {
            throw PortfolioCSVError.invalid("ожидается заголовок ticker,shares,average_cost.")
        }
        guard rows.count > 1, rows.count <= 10_001 else { throw PortfolioCSVError.invalid("нужно от 1 до 10 000 позиций.") }
        return try rows.dropFirst().enumerated().map { index, columns in
            guard columns.count == 3,
                  let shares = Double(columns[1].trimmingCharacters(in: .whitespaces)),
                  let cost = Double(columns[2].trimmingCharacters(in: .whitespaces)) else {
                throw PortfolioCSVError.invalid("некорректные поля в записи \(index + 2).")
            }
            let position = PortfolioPosition(ticker: columns[0], shares: shares, averageCost: cost)
            guard position.isValid else { throw PortfolioCSVError.invalid("некорректный тикер, количество или цена в записи \(index + 2).") }
            return position
        }
    }
}