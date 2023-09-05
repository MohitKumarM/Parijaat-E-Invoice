pageextension 50502 PostedSalesCrMemos extends "Posted Sales Credit Memos"
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
        }
    }

    actions
    {
        addafter("&Print")
        {
            action(CreateIRNNo)
            {
                Caption = 'Create-IRN No';
                Promoted = true;
                ApplicationArea = All;

                trigger OnAction()
                var
                    APICall: Codeunit "ROBOAPI Call Cloud";
                begin
                    //LFS-5335 ++
                    CLEAR(APICall);
                    APICall.GenerateEInvoice(Rec."No.", 3, true);
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
                    APICall.CancelIRN(Rec."No.", 3, Rec."Location Code", Rec."Reason Code");
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
                    APICall.GetIRNByTyeDocDetails(Rec."No.", 3);
                    //LFS-5335 --
                end;
            }

            action(ModifySalesCrMemoHeader)
            {
                Caption = 'Modify Sales Cr Memo Header';
                Promoted = true;
                PromotedCategory = Process;
                RunObject = Page "Modify Sales Cr Memo Header";
                RunPageLink = "No." = field("No.");
                ApplicationArea = All;

                trigger OnAction()
                var
                begin
                end;
            }
        }
    }
}