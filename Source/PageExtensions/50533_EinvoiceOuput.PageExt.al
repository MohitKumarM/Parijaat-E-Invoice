pageextension 50533 pageextension50017 extends "E-Invoice Output"
{
    layout
    {
        addafter("API Pay Load")
        {
            field("Output Payload E- Invoice"; OuputJSONTxt)
            {
                ApplicationArea = all;
            }
            field("Output Payload E-Way Bill"; OuputJsonEWayBill)
            {
                ApplicationArea = all;
            }
            field("Generate Invoice Details"; GenerateInvoiceDetails)
            {
                ApplicationArea = all;
            }
            field("Output Invoice Details"; OutPutInvoiceDetails)
            {
                ApplicationArea = all;
            }
        }
    }

    actions
    {
        addlast(Reporting)
        {
            action("Ouput Payload")
            {
                ApplicationArea = All;
                Promoted = true;
                trigger OnAction()
                var
                    Instrm: InStream;
                    ReturnText: Text;
                begin
                    Rec.CalcFields("Output Payload E-Invoice");
                    If rec."Output Payload E-Invoice".HasValue() then begin
                        rec."Output Payload E-Invoice".CreateInStream(Instrm);
                        Instrm.Read(ReturnText);
                        Message(ReturnText);
                    end;
                end;
            }
            action("Json Payload")
            {
                ApplicationArea = All;
                Promoted = true;
                trigger OnAction()
                var
                    Instrm: InStream;
                    ReturnText: Text;
                    Text001: Label 'Parijat C&F';
                    Test: Notification;
                begin
                    Rec.CalcFields(JSON);
                    If rec.JSON.HasValue() then begin
                        rec.JSON.CreateInStream(Instrm);
                        Instrm.Read(ReturnText);
                        Message(ReturnText);
                    end;
                end;
            }
            action("Generate Invoice Payload")
            {
                ApplicationArea = All;
                Promoted = true;
                trigger OnAction()
                var
                    Instrm: InStream;
                    ReturnText: Text;
                    Text001: Label 'Parijat C&F';
                    Test: Notification;
                begin
                    Rec.CalcFields("Generate Invoice Details");
                    If rec."Generate Invoice Details".HasValue() then begin
                        rec."Generate Invoice Details".CreateInStream(Instrm);
                        Instrm.Read(ReturnText);
                        Message(ReturnText);
                    end;
                end;
            }
            action("Output E-Way Payload")
            {
                ApplicationArea = All;
                Promoted = true;
                trigger OnAction()
                var
                    Instrm: InStream;
                    ReturnText: Text;
                    Text001: Label 'Parijat C&F';
                    Test: Notification;
                begin
                    Rec.CalcFields("Output Payload Invoice Details");
                    If rec."Output Payload Invoice Details".HasValue() then begin
                        rec."Output Payload Invoice Details".CreateInStream(Instrm);
                        Instrm.Read(ReturnText);
                        Message(ReturnText);
                    end;
                end;
            }
        }
    }

    var
        OuputJSONTxt: Text;
        OuputJsonEWayBill: Text;
        GenerateInvoiceDetails: Text;
        OutPutInvoiceDetails: Text;

    trigger OnAfterGetRecord()
    var
        myInt: Integer;
    begin
        OuputJSONTxt := Rec.GetOuputPayloadEInvoie();
        OuputJsonEWayBill := Rec.GetOuputPayloadEWayBill();
        GenerateInvoiceDetails := Rec.GetGeneratePayloadEWayBill();
        OutPutInvoiceDetails := Rec.GetOutPutPayloadEWayBill();


    end;
}