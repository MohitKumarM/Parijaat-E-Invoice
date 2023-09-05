pageextension 50509 PostedSalesInvoices extends "Posted Sales Invoices"
{
    layout
    {
        addafter("Location Code")
        {
            field("QR Code"; Rec."QR Code")
            {
                ToolTip = 'Specifies the value of the QR Code field.';
                ApplicationArea = All;
            }
            field("IRN No."; Rec."IRN No.")
            {
                ToolTip = 'Specifies the value of the IRN No. field.';
                ApplicationArea = All;
            }

            field("E-Way Bill No."; Rec."E-Way Bill No.")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the E-way bill number on the sale document.';
            }
            field("E-Way Bill Date"; Rec."E-Way Bill Date")
            {
                ApplicationArea = All;
                ToolTip = 'Specifies the value of the E-Way Bill Date field.';
            }
            field("B2C QR Code"; Rec."B2C QR Code")
            {
                ApplicationArea = all;
            }
        }
    }

    actions
    {
        addafter(Print)
        {
            action(CreateIRNNo)
            {
                Caption = 'Create IRN No';
                Promoted = true;
                ApplicationArea = All;

                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    //LFS-5335 ++
                    CLEAR(APICall);
                    APICall.GenerateEInvoice(rec."No.", 2, true);
                    //LFS-5335 --
                end;
            }
            action(CheckIRNNo)
            {
                Caption = 'Check IRN No';
                Promoted = true;
                ApplicationArea = All;

                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    //LFS-5335 ++
                    CLEAR(APICall);
                    APICall.GenerateEInvoice(rec."No.", 2, false);
                    //LFS-5335 --
                end;
            }
            action(CancelIRN)
            {
                Caption = 'Cancel IRN No.';
                Promoted = true;
                ApplicationArea = All;
                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    //LFS-5335 ++
                    Rec.TESTFIELD("Reason Code");
                    CLEAR(APICall);
                    APICall.CancelIRN(Rec."No.", 2, Rec."Location Code", Rec."Reason Code");
                    //LFS-5335 --
                end;
            }
            action("Get IRN By Doc No")
            {
                Caption = 'Get IRN By Doc No.';
                Promoted = true;
                ApplicationArea = All;
                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    //LFS-5335 ++
                    CLEAR(APICall);
                    //APICall.GetIRNByDocDetails("No.",2);
                    APICall.GetIRNByTyeDocDetails(Rec."No.", 2);
                    //LFS-5335 --
                end;
            }

            action(ModifySalesInvHeader)
            {
                Caption = 'Modify Sales Inv Header';
                Promoted = true;
                RunObject = Page "Modify Sales Inv Header";
                RunPageLink = "No." = field("No.");
                ApplicationArea = All;
            }
            action(Test)
            {
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                Visible = false;

                trigger OnAction()
                var
                    JOutputObject: JsonObject;
                    JOutputToken: JsonToken;
                    JResultToken: JsonToken;
                    JResultObject: JsonObject;
                    OutputMessage: Text;
                    ResultMessage: Text;
                    EWayBillNo: Text[30];
                    EWayBillDateTime: Variant;
                    EWayExpiryDateTime: Variant;
                    TestJson: JsonObject;
                    TestArray: JsonArray;
                    TestJson2: JsonObject;
                    TestJson3: JsonObject;
                    JResultArray: JsonArray;
                    JItemArray: JsonArray;

                begin
                    TestJson.Add('statusCd', '1');
                    TestJson.Add('refId', '');
                    TestJson.Add('data', TestJson2);

                    TestJson3.Add('sGstin', '09AAACO0305P1ZF');
                    TestJson3.Add('ewb', '461330207505');
                    TestJson3.Add('ewbDate', 'Apr 18, 2023 11:48:00 AM');
                    TestJson3.Add('validUpTo', 'Apr 19, 2023 11:59:00 PM');
                    TestArray.Add(TestJson3);
                    TestJson2.Add('success', TestArray);
                    //JItemObject.Add('test', '1');
                    //JItemArray.Add(JItemObject);
                    TestJson2.Add('error', JItemArray);
                    TestJson.WriteTo(ResultMessage);

                    JResultObject.ReadFrom(ResultMessage);

                    Message(ResultMessage);
                    if JResultObject.Get('error', JResultToken) then
                        if JResultToken.IsArray then begin
                            JResultToken.WriteTo(OutputMessage);
                            if OutputMessage = '[]' then begin
                                //JResultArray.ReadFrom(OutputMessage);
                                if JResultObject.Get('data', JResultToken) then
                                    if JResultToken.IsObject then begin
                                        JResultToken.WriteTo(OutputMessage);
                                        JOutputObject.ReadFrom(OutputMessage);
                                    end;
                                if JOutputObject.Get('success', JOutputToken) then
                                    if JOutputToken.IsArray then begin
                                        JOutputToken.WriteTo(OutputMessage);
                                        JResultArray.ReadFrom(OutputMessage);
                                        if JResultArray.Get(0, JOutputToken) then begin
                                            if JOutputToken.IsObject then begin
                                                JOutputToken.WriteTo(OutputMessage);
                                                JOutputObject.ReadFrom(OutputMessage);
                                            end;
                                        end;
                                    end;
                                if JOutputObject.Get('ewb', JOutputToken) then
                                    EWayBillNo := JOutputToken.AsValue().AsText();
                                if JOutputObject.Get('ewbDate', JOutputToken) then
                                    EWayBillDateTime := JOutputToken.AsValue().AsText();
                                if JOutputObject.Get('ewb', JOutputToken) then
                                    EWayBillNo := JOutputToken.AsValue().AsText();
                                if JOutputObject.Get('validUpTo', JOutputToken) then
                                    EWayExpiryDateTime := JOutputToken.AsValue().AsText();
                            end;
                        end;
                end;
            }
            action("Generate Invoice Detail")
            {
                ApplicationArea = All;
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "Generate EwaySalesInvoiceCloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.GenerateInvoiceDetails(Rec."No.", 2);
                end;
            }
            action("CalculateDistance")
            {
                Caption = 'Calculate Distance';
                ApplicationArea = All;
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "Generate EwaySalesInvoiceCloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.CalculateDistance(Rec."No.", 2);
                end;
            }
            action("GeneratePartA")
            {
                Caption = 'Generate Part A';
                ApplicationArea = All;
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "Generate EwaySalesInvoiceCloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.GeneratePARTA(Rec."No.", 2);
                end;
            }
            action("UpdatePartB")
            {
                Caption = 'Generate Part B';
                ApplicationArea = All;
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "Generate EwaySalesInvoiceCloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.UPDATEPARTB(Rec."No.", 2);
                end;
            }
            action("CancelEWayBill1")
            {
                ApplicationArea = All;
                Caption = 'Cancel E-Way Bill';
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "Generate EwaySalesInvoiceCloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.CancelEwayBill(Rec."No.", 2);
                end;
            }
            action("UpdateTransporter")
            {
                ApplicationArea = All;
                Caption = 'Update Transporter';
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "Generate EwaySalesInvoiceCloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.UpdateTransporter(Rec."No.", 2, Rec."Shipping Agent Code");
                end;
            }
            action("ExtendedValidity")
            {
                ApplicationArea = All;
                Caption = 'Extended Validity';
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "Generate EwaySalesInvoiceCloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.ExtendValidity(Rec."No.", 2);
                end;
            }


            action("DownloadEWayBill")
            {
                ApplicationArea = All;
                Caption = 'Download E-Way Bill';
                Promoted = true;

                trigger OnAction()
                var
                    EwayBillAPI: Codeunit "Generate EwaySalesInvoiceCloud";
                begin
                    CLEAR(EwayBillAPI);
                    EwayBillAPI.DownloadEwayBillPDF(Rec."No.", 2);
                end;
            }
            action("Generate B2C QR1")
            {
                ApplicationArea = All;
                Caption = 'Generate B2C QR';
                Promoted = true;

                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    //6587 ++
                    CLEAR(APICall);
                    APICall.GenerateDynamicsQR(Rec."No.");
                    //6587 --
                end;
            }
        }
    }
}