import json

from django.http import JsonResponse
from django.templatetags.static import static
from .models import Order, OrderItem


from .models import Product


def banners_list_api(request):
    # FIXME move data to db?
    return JsonResponse([
        {
            'title': 'Burger',
            'src': static('burger.jpg'),
            'text': 'Tasty Burger at your door step',
        },
        {
            'title': 'Spices',
            'src': static('food.jpg'),
            'text': 'All Cuisines',
        },
        {
            'title': 'New York',
            'src': static('tasty.jpg'),
            'text': 'Food is incomplete without a tasty dessert',
        }
    ], safe=False, json_dumps_params={
        'ensure_ascii': False,
        'indent': 4,
    })


def product_list_api(request):
    products = Product.objects.select_related('category').available()

    dumped_products = []
    for product in products:
        dumped_product = {
            'id': product.id,
            'name': product.name,
            'price': product.price,
            'special_status': product.special_status,
            'description': product.description,
            'category': {
                'id': product.category.id,
                'name': product.category.name,
            } if product.category else None,
            'image': product.image.url,
            'restaurant': {
                'id': product.id,
                'name': product.name,
            }
        }
        dumped_products.append(dumped_product)
    return JsonResponse(dumped_products, safe=False, json_dumps_params={
        'ensure_ascii': False,
        'indent': 4,
    })


def register_order(request):
    if request.method == 'POST':
        try:
            payload = json.loads(request.body)

            order = Order.objects.create(
                client_name = payload.get('firstname'),
                surname = payload.get('lastname'),
                phone = payload.get('phonenumber'),
                delivery_address = payload.get('address')
            )

            product_in_payload = payload.get('products')

            for product in product_in_payload:
                product_id = product.get('product')
                quantity = product.get('quantity')

                product_object = Product.objects.get(id=product_id)

                OrderItem.objects.create(
                    order=order,
                    product=product_object,
                    quantity=quantity
                )

            return JsonResponse({'order_id': order.id})
        except json.JSONDecodeError:
            print("Ошибка декодирования JSON из тела запроса")
            return JsonResponse({'error': 'Invalid JSON'}, status=400)
        except Exception as e:
            print(f"Неожиданная ошибка: {e}")
            return JsonResponse({'error': 'Server error'}, status=500)

    return JsonResponse({'error': 'Допустим только POST-запрос'}, status=405)
