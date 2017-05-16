WebBanking {
    version = 1.0,
    url = "https://www.mintos.com/",
    services = { "Mintos Account" }
}

local connection

function SupportsBank (protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "Mintos Account"
end

function InitializeSession (protocol, bankCode, username, username2, password, username3)
    connection = Connection() 
    local html = HTML(connection:get(url))
    local csrfToken = html:xpath("//*[@id='login-form']/input[@name='_csrf_token']"):val()

    content, charset, mimeType = connection:request("POST",
    "https://www.mintos.com/en/login/check",
    "_username=" .. username .. "&_password=" .. password .. "&_csrf_token=" .. csrfToken,
    "application/x-www-form-urlencoded; charset=UTF-8")

    if string.match(connection:getBaseURL(), 'login') then
        return LoginFailed
    end
end

function ListAccounts (knownAccounts)
    local html = HTML(connection:get("https://www.mintos.com/en/my-settings/"))
    local accountNumber = html:xpath("//*/table[contains(concat(' ', normalize-space(@class), ' '), ' js-investor-settings ')]/tr[1]/td[@class='data']"):text()

    local accounts = {}

    table.insert(accounts, {
        name = 'Available Funds',
        accountNumber = accountNumber .. '-1',
        currency = "EUR",
        type = AccountTypeGiro
    })

    table.insert(accounts, {
        name = 'Invested Funds',
        accountNumber = accountNumber .. '-2',
        currency = "EUR",
        portfolio = true,
        type = AccountTypePortfolio
    })

    return accounts
end

function RefreshAccount (account, since)
    local datePattern = "(%d+)%.(%d+)%.(%d+).*%s(%d+):(%d+)"
    
    if string.sub(account.accountNumber, -1) == '1' then
        local list = HTML(connection:request("POST",
        "https://www.mintos.com/en/account-statement/list",
        "account_statement_filter[fromDate]=" .. os.date("%d.%m.%Y", since) .. "&account_statement_filter[toDate]=" .. os.date("%d.%m.%Y", os.time()) .. "",
        "application/x-www-form-urlencoded; charset=UTF-8"))

        local balance = list:xpath('//*[@id="overview-details"]/table/tbody/tr[last()]/td[1]/span[2]'):text()

        local transactions = {}

        list:xpath('//*[@id="overview-details"]/table/tbody/tr[not(@class)]'):each(function (index, element)
            local dateString = element:xpath('.//*[@class="m-transaction-date"]'):attr('title')
            local day, month, year, hour, min = dateString:match(datePattern)

            local purpose = element:xpath('.//*[@class="m-transaction-details"]'):text()

            local amount = element:xpath('.//*[contains(concat(" ", normalize-space(@class), " "), " m-transaction-amount ")]'):text()

            local transaction = {
                bookingDate = os.time({day=day,month=month,year=year,hour=hour,min=min}),
                purpose = purpose,
                amount = tonumber(amount)
            }
            table.insert(transactions, transaction)
        end)

        return {
            balance = balance,
            transactions = transactions
        }
    else
        local list = HTML(connection:request("POST",
        "https://www.mintos.com/en/my-investments/list",
        "statuses%5B%5D=256&statuses%5B%5D=512&statuses%5B%5D=1024&statuses%5B%5D=2048&statuses%5B%5D=8192&statuses%5B%5D=16384&max_results=100&page=1",
        "application/x-www-form-urlencoded; charset=UTF-8"))
        
        local securities = {}

        list:xpath('//*[@id="investor-investments-table"]/tbody/tr[not(contains(@class, "total-row"))]'):each(function (index, element)
            local dateOfPurchaseString = element:xpath('.//*[contains(concat(" ", normalize-space(@class), " "), " m-loan-issued ")]'):attr('title')
            local day, month, year, hour, min = dateOfPurchaseString:match(datePattern)
            
            local name = element:xpath('.//*[contains(concat(" ", normalize-space(@class), " "), " m-loan-id ")]'):text()
            local price = string.match(element:xpath('.//*[@data-m-label="Outstanding Principal"]'):text(), ".*%s(%d+%.%d+).*")
            
            local security = {
                dateOfPurchase = os.time({day=day,month=month,year=year,hour=hour,min=min}),
                name = name,
                currency = 'EUR',
                amount = tonumber(price)
            }
            table.insert(securities, security)
        end)

        return {securities = securities}
    end
end

function EndSession ()
    connection:get("https://www.mintos.com/")
    connection:get("https://www.mintos.com/en/logout")
    return nil
end
