pageextension 50531 States extends States
{
    layout
    {
        addafter(Description)
        {
            field("State Code for E-Invoicing"; Rec."State Code for E-Invoicing")
            {
                ToolTip = 'Specifies the value of the State Code for E-Invoicing field.';
                ApplicationArea = All;
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