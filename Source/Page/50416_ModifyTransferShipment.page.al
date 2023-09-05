page 50416 "Modify TransferShipment Header"
{
    Permissions = tabledata 5744 = rm;
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "Transfer Shipment Header";


    layout
    {
        area(Content)
        {
            repeater(GroupName)
            {
                field("No."; Rec."No.")
                {
                    ApplicationArea = all;
                }

                field("Vehicle No."; Rec."Vehicle No.")
                {
                    Caption = 'Vehicle No.';
                    ApplicationArea = All;
                }
                field("Vehicle Type"; Rec."Vehicle Type")
                {
                    Caption = 'Vehicle Type';
                    ApplicationArea = all;
                }
                field("Distance (Km)"; Rec."Distance (Km)")
                {
                    ApplicationArea = all;
                }
                field("Cancel Reason"; Rec."Cancel Reason")
                {
                    ApplicationArea = all;
                }
                field("Cancel Remarks"; Rec."Cancel Remarks")
                {
                    ApplicationArea = all;
                }
                field("Transporter Code"; Rec."Transporter Code")
                {
                    ApplicationArea = all;
                }
                field("Transport Method"; Rec."Transport Method")
                {
                    ApplicationArea = all;
                    Editable = true;
                }
            }
        }
        area(Factboxes)
        {

        }
    }

    actions
    {
        area(Processing)
        {
            action(ActionName)
            {
                ApplicationArea = All;

                trigger OnAction();
                begin

                end;
            }
        }
    }
}