pageextension 50515 pageextension50515 extends Currencies
{
    layout
    {
        addafter("ISO Numeric Code")
        {
            field("Country Code For E-invoicing"; Rec."Country Code For E-invoicing")
            {
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