page 50413 "E-Invoice API Set Up"
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "E-Invoice Set Up 1";

    layout
    {
        area(Content)
        {
            group(GroupName)
            {
                field("Client ID"; Rec."Client ID")
                {
                    ToolTip = 'Specifies the value of the Client ID field.';
                    ApplicationArea = All;
                }
                field("Client Secret"; Rec."Client Secret")
                {
                    ToolTip = 'Specifies the value of the Client Secret field.';
                    ApplicationArea = All;
                }
                field("IP Address"; Rec."IP Address")
                {
                    ToolTip = 'Specifies the value of the IP Address field.';
                    ApplicationArea = All;
                }
                field("Authentication URL"; Rec."Authentication URL")
                {
                    ToolTip = 'Specifies the value of the Authentication URL field.';
                    ApplicationArea = All;
                }
                field("E-Invoice URl"; Rec."E-Invoice URl")
                {
                    ToolTip = 'Specifies the value of the E-Invoice URl field.';
                    ApplicationArea = All;
                }
                field("URL Get IRN"; Rec."URL Get IRN")
                {
                    ApplicationArea = all;
                }
                field("GL Account Round 1"; Rec."GL Account Round 1")
                {
                    ApplicationArea = all;
                }
                field("GL Account Round 2"; Rec."GL Account Round 2")
                {
                    ApplicationArea = all;
                }
                field("Download E-Way Bill URL"; Rec."Download E-Way Bill URL")
                {
                    ApplicationArea = all;
                    Visible = false;
                }
                field("Download IP"; Rec."Download IP")
                {
                    ApplicationArea = all;
                    Visible = false;
                }
                field("Private Key"; Rec."Private Key")
                {
                    ApplicationArea = all;
                }
                field("Private Value"; Rec."Private Value")
                {
                    ApplicationArea = all;
                }
                field("Private IP"; Rec."Private IP")
                {
                    ApplicationArea = all;
                }
                field("E-Way Bill URL"; Rec."E-Way Bill URL")
                {
                    ApplicationArea = all;
                }
                field("Cancel E-Way URL"; Rec."Cancel E-Way URL")
                {
                    ApplicationArea = all;
                    Visible = false;
                }
                field("Dynamics QR URL"; Rec."Dynamics QR URL")
                {
                    ApplicationArea = all;

                }
            }
        }

    }

    actions
    {
        area(Processing)
        {
            action(ActionName)
            {
                ApplicationArea = All;

                trigger OnAction()
                begin

                end;
            }
        }
    }

    var
        myInt: Integer;
}