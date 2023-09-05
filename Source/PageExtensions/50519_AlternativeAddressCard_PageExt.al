pageextension 50519 AlternativeAddress extends "Alternative Address Card"
{
    layout
    {
        addafter("Phone No.")
        {
            field(EIN_State; Rec.EIN_State)
            {
                Caption = 'E-Invoice State Code';
                ApplicationArea = all;
            }
        }
    }

    actions
    {
        // Add changes to page actions here
    }

    var
        myInt: Integer;
}