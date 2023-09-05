pageextension 50505 GSTRegistrationNo extends "GST Registration Nos."
{
    layout
    {
        addafter("Input Service Distributor")
        {
            field("User Name"; Rec."User Name")
            {
                ToolTip = 'Specifies the value of the User Name field.';
                ApplicationArea = All;
            }
            /* field(Password; Rec.Password)
            {
                ToolTip = 'Specifies the value of the Password field.';
                ApplicationArea = All;
            } */
        }
    }


    actions
    {
        // Add changes to page actions here
    }

    var
        myInt: Integer;
}