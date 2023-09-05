tableextension 50514 tableextension50514 extends "E-Invoice Output"
{
    fields
    {
        // Add changes to table fields here
        field(50000; "Output Payload E-Invoice"; Blob)
        {
            Subtype = Bitmap;
        }
        field(50001; "Output Payload E-Way Bill"; Blob)
        {
            Subtype = Bitmap;
        }
        field(50102; "Generate Invoice Details"; Blob)
        {
            Subtype = Bitmap;
        }
        field(50103; "Output Payload Invoice Details"; Blob)
        {
            Subtype = Bitmap;
        }
    }

    var
        myInt: Integer;

    procedure GetOuputPayloadEInvoie(): Text
    var
        CR: Text[1];
        instr: InStream;
        Encoding: TextEncoding;
        ContentLine: Text;
        Content: Text;
    begin
        CALCFIELDS("Output Payload E-Invoice");
        IF NOT "Output Payload E-Invoice".HASVALUE THEN
            EXIT('');
        CR[1] := 10;
        Clear(Content);
        Clear(instr);
        "Output Payload E-Invoice".CreateInStream(instr, TextEncoding::Windows);
        instr.READTEXT(Content);
        WHILE NOT instr.EOS DO BEGIN
            instr.READTEXT(ContentLine);
            Content += CR[1] + ContentLine;
        END;
        exit(Content);
    end;

    procedure GetOuputPayloadEWayBill(): Text
    var
        CR: Text[1];
        instr: InStream;
        Encoding: TextEncoding;
        ContentLine: Text;
        Content: Text;
    begin
        CALCFIELDS("Output Payload E-Way Bill");
        IF NOT "Output Payload E-Way Bill".HASVALUE THEN
            EXIT('');
        CR[1] := 10;
        Clear(Content);
        Clear(instr);
        "Output Payload E-Way Bill".CreateInStream(instr, TextEncoding::Windows);
        instr.READTEXT(Content);
        WHILE NOT instr.EOS DO BEGIN
            instr.READTEXT(ContentLine);
            Content += CR[1] + ContentLine;
        END;
        exit(Content);
    end;

    procedure GetGeneratePayloadEWayBill(): Text
    var
        CR: Text[1];
        instr: InStream;
        Encoding: TextEncoding;
        ContentLine: Text;
        Content: Text;
    begin
        CALCFIELDS("Generate Invoice Details");
        IF NOT "Generate Invoice Details".HASVALUE THEN
            EXIT('');
        CR[1] := 10;
        Clear(Content);
        Clear(instr);
        "Generate Invoice Details".CreateInStream(instr, TextEncoding::Windows);
        instr.READTEXT(Content);
        WHILE NOT instr.EOS DO BEGIN
            instr.READTEXT(ContentLine);
            Content += CR[1] + ContentLine;
        END;
        exit(Content);
    end;

    procedure GetOutPutPayloadEWayBill(): Text
    var
        CR: Text[1];
        instr: InStream;
        Encoding: TextEncoding;
        ContentLine: Text;
        Content: Text;
    begin
        CALCFIELDS("Output Payload Invoice Details");
        IF NOT "Output Payload Invoice Details".HASVALUE THEN
            EXIT('');
        CR[1] := 10;
        Clear(Content);
        Clear(instr);
        "Output Payload Invoice Details".CreateInStream(instr, TextEncoding::Windows);
        instr.READTEXT(Content);
        WHILE NOT instr.EOS DO BEGIN
            instr.READTEXT(ContentLine);
            Content += CR[1] + ContentLine;
        END;
        exit(Content);
    end;
}