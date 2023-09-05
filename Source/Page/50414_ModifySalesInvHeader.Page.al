page 50414 "Modify Sales Inv Header"
{
    Permissions = tabledata 112 = rm;
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "Sales Invoice Header";


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
                field("LR/RR No."; Rec."LR/RR No.")
                {
                    ApplicationArea = all;
                }
                field("Shipping Agent Code"; Rec."Shipping Agent Code")
                {
                    ApplicationArea = all;
                }
                field("Transport Method"; Rec."Transport Method")
                {
                    ApplicationArea = All;
                }
                field("Vehicle Change Reason"; Rec."Vehicle Change Reason")
                {
                    ApplicationArea = all;
                }
                field("LR/RR Date"; Rec."LR/RR Date")
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
                field("Reason Code"; Rec."Reason Code")
                {
                    ApplicationArea = all;
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