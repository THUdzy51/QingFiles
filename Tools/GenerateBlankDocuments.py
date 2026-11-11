"""Rebuild bundled blank documents with python-docx, openpyxl and python-pptx.

Development-only dependencies. The app uses the checked-in files directly.
All resources are original blank documents, without user content.
"""
from datetime import datetime
from pathlib import Path
from docx import Document
from openpyxl import Workbook
from pptx import Presentation

output = Path(__file__).resolve().parent.parent / 'Resources' / 'BlankDocuments'
output.mkdir(parents=True, exist_ok=True)
stamp = datetime(2000, 1, 1)
document = Document()
document.add_paragraph()
presentation = Presentation()
presentation.slides.add_slide(presentation.slide_layouts[6])
for item, extension in [(document, 'docx'), (presentation, 'pptx')]:
    props = item.core_properties
    props.author = 'QingFiles contributors'
    props.last_modified_by = ''
    props.title = ''
    props.subject = ''
    props.comments = ''
    props.created = stamp
    props.modified = stamp
    item.save(output / f'Blank.{extension}')
workbook = Workbook()
workbook.properties.creator = 'QingFiles contributors'
workbook.properties.lastModifiedBy = ''
workbook.properties.created = stamp
workbook.properties.modified = stamp
workbook.save(output / 'Blank.xlsx')

# A single blank A4 page. Build byte offsets for the PDF cross-reference table.
objects = [
    b'<< /Type /Catalog /Pages 2 0 R >>',
    b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << >> >>',
]
pdf = bytearray(b'%PDF-1.4\n')
offsets = [0]
for number, body in enumerate(objects, 1):
    offsets.append(len(pdf))
    pdf.extend(f'{number} 0 obj\n'.encode() + body + b'\nendobj\n')
xref = len(pdf)
pdf.extend(b'xref\n0 4\n0000000000 65535 f \n')
for offset in offsets[1:]:
    pdf.extend(f'{offset:010} 00000 n \n'.encode())
pdf.extend(f'trailer\n<< /Size 4 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
(output / 'Blank.pdf').write_bytes(pdf)
