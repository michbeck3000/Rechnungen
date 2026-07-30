
import sys

file_path = '/Users/michbeck/XCode/Rechnungen/Rechnungen/ContentView.swift'
with open(file_path, 'r') as f:
    lines = f.readlines()

new_lines = []
for i, line in enumerate(lines):
    new_lines.append(line)
    
    # NewRechnungView: After amount HStack closing brace (Line 486 in previous view)
    # Corrected line check based on 'sed' output: line 485 in 0-indexed is line 486
    if i == 485:
        new_lines.append('\n')
        new_lines.append('                    TextField("IBAN (optional)", text: $iban)\n')
        new_lines.append('                        .keyboardType(.asciiCapable)\n')
        new_lines.append('                        .textInputAutocapitalization(.characters)\n')
        new_lines.append('                        .submitLabel(.done)\n')

    # EditRechnungView: After amount HStack closing brace (Line 782 in previous view)
    # Corrected line check based on 'sed' output: line 781 in 0-indexed is line 782
    if i == 781:
        new_lines.append('\n')
        new_lines.append('                    TextField("IBAN (optional)", text: $iban)\n')
        new_lines.append('                        .keyboardType(.asciiCapable)\n')
        new_lines.append('                        .textInputAutocapitalization(.characters)\n')
        new_lines.append('                        .submitLabel(.done)\n')

with open(file_path, 'w') as f:
    f.writelines(new_lines)
print("Fields successfully reordered.")
