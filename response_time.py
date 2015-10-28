##   How to use ?
##   python response_time.py https://tw.yahoo.com
##
##
import requests
import sys


test_site = str(sys.argv[1])

total = 0
for i in range(1,101):
	response = requests.get(test_site).elapsed.total_seconds()
        total = total + response
	print '{0}={1}'.format(i, response)

print '{0}--->Average Time={1}'.format(test_site, total/100)
