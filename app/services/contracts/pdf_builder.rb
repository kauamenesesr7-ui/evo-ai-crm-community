module Contracts
  class PdfBuilder
    def initialize(contract)
      @contract = contract
    end

    def call
      lines = document_lines.first(48)
      stream = ["BT", "/F1 11 Tf", "50 790 Td"]
      lines.each_with_index do |line, index|
        stream << '0 -15 Td' if index.positive?
        stream << "(#{escape(line)}) Tj"
      end
      stream << 'ET'
      stream_data = stream.join("\n")

      objects = [
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
        "<< /Length #{stream_data.bytesize} >>\nstream\n#{stream_data}\nendstream",
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
      ]

      build_pdf(objects)
    end

    private

    def document_lines
      body = ActionView::Base.full_sanitizer.sanitize(@contract.content.to_s)
      [
        @contract.title,
        "Contrato: #{@contract.number}",
        "Emitido em: #{@contract.issued_on.strftime('%d/%m/%Y')}",
        '',
        *body.scan(/.{1,82}(?:\s+|\z)/).map(&:strip),
        '',
        signature_line,
        ("Integridade SHA-256: #{@contract.document_hash}" if @contract.document_hash.present?)
      ].compact.map { |line| I18n.transliterate(line.to_s) }
    end

    def signature_line
      return 'Assinatura da empresa: pendente' unless @contract.signed?

      "Assinado pela empresa por #{@contract.company_signer_name.presence || 'responsavel'} em #{@contract.signed_at.strftime('%d/%m/%Y %H:%M')}"
    end

    def escape(text)
      text.gsub(/[\\()]/) { |char| "\\#{char}" }
    end

    def build_pdf(objects)
      pdf = +"%PDF-1.4\n"
      offsets = [0]
      objects.each_with_index do |object, index|
        offsets << pdf.bytesize
        pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
      end
      xref_offset = pdf.bytesize
      pdf << "xref\n0 #{objects.length + 1}\n"
      pdf << "0000000000 65535 f \n"
      offsets.drop(1).each { |offset| pdf << format('%010d 00000 n ', offset) << "\n" }
      pdf << "trailer\n<< /Size #{objects.length + 1} /Root 1 0 R >>\n"
      pdf << "startxref\n#{xref_offset}\n%%EOF\n"
      pdf
    end
  end
end
